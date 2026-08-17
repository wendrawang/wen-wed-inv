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

`onCreateNavigationLinks()` mengembalikan `AnyView`, dan itu ada di jalur render
setiap layar. `identifier` juga menjalankan refleksi
(`String(describing: type(of: self))`) pada setiap evaluasi — kecil, tapi
gratis untuk dihilangkan.

`PrimitiveAddContactForm` **bukan** masalah; lihat koreksi di bawah.

---

## 5. Koreksi: `setHidden` sudah benar

Saya sempat menduga `.setHidden` menyisakan view di hierarki. Itu **salah**.

```swift
func setHidden(
    _ isHidden: Bool,
    isRemove: Bool = true,
    ...
) -> some View

// HiddenViewModifier
func body(content: Content) -> some View {
    Group {
        if isHidden {
            renderEmptyView(content: content)   // isRemove == true → emptyContent saja
        } else {
            content
        }
    }
}
```

Default `isRemove: true` benar-benar **mengeluarkan** view dari hierarki lewat
cabang `if`/`else` di ViewBuilder. Dua kekhawatiran saya sebelumnya gugur:

- `renderSheetView()` **tidak** membangun enam representable sekaligus. Hanya
  cabang yang cocok dengan `sheetState` yang benar-benar dibangun. Tidak ada
  view controller sia-sia.
- `PrimitiveAddContactForm` tidak dibangun di layar yang tidak memakainya —
  yang dievaluasi hanya `init` struct-nya sebagai argumen, dan itu murah.
  Membungkusnya dengan `if` tidak akan memberi apa-apa.

Hal yang sama berlaku untuk `renderScreenLoading()`: `Rectangle` dan
`ActivityIndicatorView` tidak ada di pohon saat layar tidak sedang memuat.

Satu konsekuensi yang perlu diingat: karena `setHidden` memakai cabang
ViewBuilder, mengubah nilainya **menghancurkan dan membangun ulang** isinya.
Untuk tampilan tanpa state itu tepat. Untuk view yang menyimpan state internal
atau memuat sumber daya (gambar, web view), sembunyikan-tampilkan berulang
berarti muat ulang berulang.

`invisible()` juga wajar. `.isDetailLink(false)` memang yang dibutuhkan
`NavigationView` di iOS 13–14, dan `.opacity(0)` pada `NavigationLink`
berlabel `EmptyView` praktis tidak berbiaya layout.

> Catatan penamaan: `OpacityLevels.highest` bernilai `0`. Pembaca yang wajar
> akan mengira "opacity tertinggi" berarti paling pekat. Menamainya
> `OpacityLevels.transparent` akan menghemat satu kesalahpahaman yang cepat
> atau lambat akan terjadi.

---

## 6. `ImageViewModel` tidak memuat gambar

File ini hanya menyimpan `name` / `url` / `base64` sebagai string. Tidak ada
pengunduhan, cache, decode, maupun downsampling di sini — semuanya ada di view
yang merendernya. Jadi pertanyaan terbesar untuk fps dan memori **belum
terjawab**; yang dibutuhkan adalah `ImageView` (atau apa pun yang mengubah
`url` menjadi piksel).

Yang bisa disimpulkan dari file ini:

**Identitasnya berbasis objek, bukan isi.**

```swift
let key = UUID()

static func == (lhs: ImageViewModel, rhs: ImageViewModel) -> Bool {
    lhs.key == rhs.key
}
```

Dua `ImageViewModel` dengan URL yang sama persis **tidak** dianggap sama, dan
`Identifiable` pada tipe class memakai identitas objek. Artinya mengganti
`ImageViewModel` dengan instance baru — walaupun URL-nya sama — membuat SwiftUI
melihatnya sebagai gambar yang berbeda, dan besar kemungkinan memicu pemuatan
ulang.

Ini penting untuk aturan 5 di [SCREEN_PATTERN.md](SCREEN_PATTERN.md): "selalu
assign ulang sub-ViewModel" tepat untuk tampilan biasa, tetapi **tidak** untuk
sub-ViewModel yang memiliki sumber daya mahal. Pada layar ini kebetulan aman,
karena gambar kartu ada di `headerBankCardViewModel` yang dibangun sekali lewat
`configure(with:)` dan tidak disentuh `setupView()`. Di layar lain, menaruh
gambar di sub-ViewModel yang di-assign ulang setiap refresh berarti memuat
ulang gambar setiap refresh.

**`setImage(url:)` menerbitkan lima kali berturut-turut.**

`name`, `base64`, `isMonochromeEffectApplied`, `fallbackAppearance`, lalu `url`
— semuanya `@Published`. Pada objek baru yang belum diamati itu tidak
berbiaya. Pada `ImageViewModel` yang sudah tampil di layar, satu panggilan
`setImage` berarti lima invalidasi berturut-turut untuk view yang mengamatinya.

**`onLoadImageSucceed` adalah closure tersimpan.**

Pola yang sama dengan temuan lain: kalau pemanggil mengoper `self.someMethod`,
`ImageViewModel` akan menahan objek itu, sementara objek itu biasanya juga
memegang `ImageViewModel`. Periksa call site `setImage(url:onLoadImageSucceed:)`.

**`setImage(url:)` melakukan kerja parsing setiap dipanggil** —
`removingPercentEncoding`, `addingPercentEncoding`, dan `isValidUrl`. Untuk satu
gambar tidak masalah; di dalam list yang di-scroll, ini pantas dilihat.

---

## 7. Yang perlu diukur, bukan diubah dulu

**`.blur()` di akar setiap layar.**

```swift
.blur(radius: viewModel.isRunningInBackground ? BlurLevels.low : DefaultValues.emptyCGFloat)
```

Modifier ini selalu ada di pohon, bahkan saat radiusnya nol. Filter komposit
di akar seluruh layar adalah tempat klasik lahirnya offscreen rendering. Apakah
SwiftUI memotong jalur itu saat radius nol tidak terdokumentasi, jadi ini
pertanyaan untuk Instruments (Core Animation, centang Color
Offscreen-Rendered), bukan untuk ditebak.

**`@EnvironmentObject var appState: AppState`.**

Setiap `Screen` membacanya, sehingga setiap perubahan pada `AppState`
meng-invalidasi **semua** layar yang ada di hierarki sekaligus. Seberapa besar
dampaknya tergantung seberapa sering `AppState` berubah — itu yang perlu
dicek lebih dulu.
