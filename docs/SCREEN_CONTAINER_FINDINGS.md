# Temuan di `Screen` dan `ScreenContent`

> Ditulis terhadap kode yang dikirim pada batch 3. Seperti dokumen temuan
> lainnya, ini daftar hal yang perlu dipastikan, bukan daftar pekerjaan.

---

## 1. `Screen.init` mengevaluasi `content()` seketika — terkonfirmasi

```swift
init(_ content: () -> (Content)) {
    self.content = content()
    self.contentViewModel = self.content.viewModel
}
```

Ini pertanyaan yang menggantung sejak awal, dan jawabannya menentukan skala
seluruh diagnosis. Closure-nya **tidak** disimpan; ia dipanggil langsung di
`init`.

Artinya, pada kode versi lama:

```swift
NavigationLink(
    destination: Screen {
        DetailCardInfoScreen(viewModel: createViewModel())
    },
    tag: ..., selection: ...
) { EmptyView() }
```

`Screen { ... }` dibangun saat argumen `destination:` dievaluasi — yaitu di
dalam `body` coordinator. Karena `init` memanggil `content()` seketika,
**seluruh rantai `createViewModel()` berjalan pada setiap evaluasi body setiap
coordinator**, termasuk coordinator yang layarnya tidak pernah dibuka.

Ini mengubah masalahnya dari "satu layar berperilaku aneh" menjadi "setiap
layar membayar biaya konfigurasi penuh pada setiap render induknya". Semua
efek samping yang dulu ada di `createViewModel()` — `resetState()`,
`renewIdentifier()`, `flushData()`, penulisan `@Published` — ikut berjalan
sesering itu.

`LazyNavigationLink` menutup ini karena builder-nya hanya dipanggil sekali
saat push. `Screen` sendiri tidak perlu diubah untuk itu.

---

## 2. `Screen` membuang satu `ScreenContentViewModel` pada setiap konstruksi

```swift
@ObservedObject private var contentViewModel = ScreenContentViewModel()

init(_ content: () -> (Content)) {
    self.content = content()
    self.contentViewModel = self.content.viewModel   // yang di atas dibuang
}
```

Nilai default pada stored property dievaluasi pada **setiap** init struct,
lalu langsung ditimpa. Jadi setiap kali `Screen` dibangun, satu
`ScreenContentViewModel` lengkap dialokasikan — dengan 20-an `@Published`,
dua pendaftaran `NotificationCenter`, dan beberapa closure — hanya untuk
dibuang sedetik kemudian.

Selama objek buangan itu benar-benar dilepas, biayanya "hanya" alokasi.
Tetapi kalau `init()`-nya masih membentuk retain cycle (lihat
[BASE_VIEWMODEL_FINDINGS.md](BASE_VIEWMODEL_FINDINGS.md) temuan 1), setiap
objek buangan **tetap hidup selamanya dan tetap terdaftar sebagai observer
jaringan** — menumpuk sepanjang aplikasi berjalan. Dua temuan itu saling
mengalikan.

### Perbaikan

```swift
@ObservedObject private var contentViewModel: ScreenContentViewModel
private let content: Content

init(_ content: () -> Content) {
    let content = content()
    self.content = content
    self._contentViewModel = ObservedObject(wrappedValue: content.viewModel)
}
```

Tanpa nilai default, tidak ada objek yang dibuang.

`viewModel = ScreenViewModel()` punya persoalan berbeda: ia tidak punya sumber
dari luar, jadi ia memang harus dibuat di sini — tetapi karena `@ObservedObject`
tidak memiliki objeknya, state-nya (`isRunningInBackground`) ikut hilang setiap
struct `Screen` di-init ulang. Dengan `LazyNavigationLink`, `Screen` hanya
dibangun sekali sehingga masalahnya tidak muncul. Kalau ingin benar-benar aman,
pindahkan `isRunningInBackground` ke `ScreenContentViewModel`, yang
kepemilikannya jelas ada di coordinator.

---

## 3. `loadData()` dipicu oleh `onAppear`, dan bisa lebih dari sekali

```swift
private func onAppear() {
    contentViewModel.initState()
    contentViewModel.loadData()
}
```

Ini menjawab pertanyaan terbuka dari batch 2: pemuatan data dipicu oleh view,
bukan oleh coordinator.

Konsekuensinya, **coordinator tidak boleh ikut memanggil `loadData()`** —
itu jadi pemuatan ganda. Yang wajib dilakukan coordinator hanyalah
`renewIdentifier()`, karena tanpa itu `requestLoadData()` dari `onAppear`
dilewati diam-diam.

Yang perlu diwaspadai: `onAppear` di SwiftUI iOS 13–14 **tidak dijamin
sekali**. Ia bisa menyala lagi saat kembali dari layar anak, dan pada beberapa
jalur render `NavigationView`. Untuk layar seperti Detail Card Info yang
`loadData()`-nya hanya menyalin nilai, itu tidak berbahaya. Untuk layar yang
memanggil network, itu berarti request ganda.

Kalau nanti terbukti mengganggu, tempat yang tepat untuk menjaganya adalah
`state` di base `UseCase` — misalnya menambah `.loading` sehingga
`requestLoadData()` menolak permintaan kedua selagi yang pertama berjalan.
Jangan menjaganya di tiap layar.

---

## 4. `AnyView` di body setiap layar — terkonfirmasi

```swift
func renderNavigationLinks() -> some View {
    Group {
        DefaultValues.emptyNavigationLink.invisible().accessibility(identifier: identifier)
        PrimitiveAddContactForm(viewModel: viewModel.primitiveAddContactFormViewModel)
            .setHidden(!viewModel.isContactFormEnabled)
        viewModel.onCreateNavigationLinks()
    }
}
```

Tiga hal sekaligus, dan semuanya di jalur render setiap layar.
`onCreateNavigationLinks()` mengembalikan `AnyView`. `PrimitiveAddContactForm`
dibangun di **semua** layar walaupun sebagian besar tidak memakai form kontak,
dan `.setHidden` biasanya menyisakannya di hierarki alih-alih mengeluarkannya.
Dan `identifier` menjalankan `String(describing: type(of: self))` — refleksi —
pada setiap evaluasi.

Yang paling murah diperbaiki adalah `PrimitiveAddContactForm`: bungkus dengan
`if viewModel.isContactFormEnabled` supaya benar-benar tidak dibangun saat
tidak dipakai.

---

## 5. Hal-hal yang perlu diukur, bukan diubah dulu

Tiga hal di `Screen` yang mencurigakan tetapi tidak boleh ditebak:

**`.blur()` di akar setiap layar.**

```swift
.blur(radius: viewModel.isRunningInBackground ? BlurLevels.low : DefaultValues.emptyCGFloat)
```

Modifier ini selalu ada di pohon, bahkan saat radiusnya nol. Filter komposit
di akar seluruh layar adalah tempat klasik lahirnya offscreen rendering. Apakah
SwiftUI memotong jalur itu saat radius nol tidak terdokumentasi, jadi ini
pertanyaan untuk Instruments (Core Animation, centang Color Offscreen-Rendered),
bukan untuk ditebak.

**Enam representable di dalam satu sheet.**

`renderSheetView()` membangun `PrimitiveActivityView`, `PrimitiveMessageComposer`,
`PrimitiveImagePicker`, `PrimitiveContactPicker`, `MailView`, dan `SafariView`
sekaligus, masing-masing disembunyikan dengan `.setHidden`. Kalau `.setHidden`
tidak mengeluarkannya dari hierarki, setiap sheet yang tampil berpotensi
membuat lima view controller yang tidak dipakai. `switch contentViewModel.sheetState`
akan menyisakan satu saja — tapi periksa dulu apa yang sebenarnya dilakukan
`.setHidden`.

**`@EnvironmentObject var appState: AppState`.**

Setiap `Screen` membacanya, sehingga setiap perubahan pada `AppState`
meng-invalidasi **semua** layar yang ada di hierarki sekaligus. Seberapa besar
dampaknya tergantung seberapa sering `AppState` berubah — itu yang perlu
dicek lebih dulu.
