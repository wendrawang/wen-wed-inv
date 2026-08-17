# Pola Layar — Coordinator, ViewModel, UseCase

Referensi kode ada di [`Examples/DetailCardInfo`](../Examples/DetailCardInfo).
Dokumen ini menjelaskan aturannya supaya bisa dipakai ulang di layar lain.

---

## Kasus yang mendasarinya

Gejala: nomor CVV dan nomor kartu **kadang** kosong, sementara di perangkat
lain dengan akun yang sama muncul normal.

Penyebab utamanya adalah sumber data yang tidak sinkron dengan waktu baca.
Coordinator mengisi `useCase.input.bankCard`, sedangkan ViewModel membaca
`useCase.repository.bankCard` — dan keduanya baru bertemu di dalam
`loadData()`. Versi lama memanggil `viewModel.setupView()` langsung dari
`createViewModel()`, yaitu **sebelum** `loadData()` pernah berjalan, sehingga
keempat field itu dibaca dari repository yang masih kosong.

Ini juga menjelaskan kenapa hanya sebagian layar yang kosong. Header kartu —
warna, gambar, nama, pemilik — tetap muncul karena diisi langsung dari
`debitCard`, tanpa melewati repository.

Layar tetap sering terlihat benar karena `loadData()` berjalan belakangan dan
memicu `setupView()` sekali lagi. Bug-nya intermiten karena ada tiga hal yang
menentukan apakah render pemulihan itu mendarat:

**`setupView()` menulis `@Published` di tengah evaluasi `body`.** Mengubah
state yang diamati saat SwiftUI sedang menghitung body adalah perilaku yang
tidak terdefinisi; notifikasinya bisa hilang sehingga frame yang tampil
memakai snapshot lama.

**`private let viewModel` pada struct View.** Struct di-init ulang setiap
render, jadi ViewModel beserta seluruh sub-ViewModel-nya kembali kosong, dan
apakah ia sempat terisi lagi sebelum frame berikutnya adalah soal waktu.

Keduanya sensitif terhadap frekuensi render dan beban main thread. Itulah
kenapa hasilnya berbeda antar perangkat.

### Kenapa kosongnya menetap, bukan berkedip

Dua hal di atas menjelaskan layar yang terisi terlambat. Yang menjelaskan layar
yang **tidak pernah** terisi ada di base `UseCase`:

```swift
func requestLoadData() {
    if state == .inactive {
        return          // diam, tanpa jejak
    }
    loadData()
}
```

`state` bernilai `.inactive` saat dibuat, dan satu-satunya yang mengubahnya
menjadi `.active` adalah `renewIdentifier()`. Sebuah UseCase yang belum pernah
di-`renewIdentifier()` akan menolak memuat data **tanpa mengeluh sama sekali**.

Ini bukan kasus teoretis, dan justru di sinilah cabang lama itu bermuara:

```swift
if selectionCoordinatorName != DetailDebitCardInfoCoordinator.named {
    viewModel.flushData()
    return DetailCardInfoScreenViewModel()   // useCase default → .inactive
}
```

ViewModel default membawa `useCase` default, yang `state`-nya `.inactive`.
Kalau ViewModel itu yang sampai ke layar, `loadData()`-nya no-op selamanya.
Bukan terlambat — tidak akan pernah. Itulah beda antara kedip dan layar yang
berdiri kosong sampai user keluar-masuk lagi.

Perbaikannya ada dua sisi. Sisi layar: tidak ada lagi jalur yang mengirim
ViewModel default. Sisi base: `requestLoadData()` diberi `assertionFailure`
sehingga kegagalan senyap ini berbunyi di Debug — lihat
[`Examples/Base/UseCase.swift`](../Examples/Base/UseCase.swift). Perubahan base
itu berlaku untuk seluruh halaman sekaligus dan tidak mengubah perilaku
Release, jadi aman dipasang lebih dulu.

### Yang ternyata bukan penyebab di layar ini

`renewIdentifier()` yang dipanggil pada setiap evaluasi body sempat saya duga
ikut membuang hasil fetch yang sedang berjalan. Setelah melihat base-nya,
dugaan itu **tidak berlaku untuk layar ini**: `startFetchSucceed(_:)`
memeriksa identifier secara sinkron di awal, dan `loadData()` layar ini
memanggilnya dengan identifier yang sama persis pada baris yang sama, jadi
pemeriksaannya selalu lolos.

Hazard-nya tetap nyata untuk UseCase yang **benar-benar asinkron** — di sana
repository menangkap identifier saat request dikirim dan baru melapor setelah
respons datang, sehingga `renewIdentifier()` yang jalan di sela-sela itu
membuat respons dibuang diam-diam. Aturan 7 tetap berlaku; hanya bukan bagian
dari cerita bug ini.

---

## Kenapa `setupView()` dulu dipanggil dari coordinator

Panggilan itu bukan kelalaian. Ia tambalan untuk gejala nyata: **swipe back
yang dibatalkan membuat layar jadi blank.**

Mekanismenya begini. Saat gestur swipe dimulai lalu dilepas tanpa jadi,
`selectionCoordinatorName` sempat berubah dan kembali lagi, dan setiap
perubahan itu membuat body induk dievaluasi ulang. Karena destination-nya
tidak lazy, `createViewModel()` ikut jalan lagi — dan pada saat selection
sedang bukan `named`, cabang ini yang dieksekusi:

```swift
if selectionCoordinatorName != DetailDebitCardInfoCoordinator.named {
    viewModel.flushData()
    return DetailCardInfoScreenViewModel()   // ← ViewModel kosong ke layar
}
```

Layar yang masih ter-push menerima ViewModel yang belum dikonfigurasi sama
sekali. Itulah blank screen-nya. Lalu selection kembali ke `named`, body jalan
lagi, dan `setupView()` pada cabang satunya mengisi ulang layar. Jadi
`setupView()` di `createViewModel()` adalah **jalur pemulihan dari blank yang
disebabkan fungsi itu sendiri**.

Niat di balik cabang itu benar: jangan bangun ViewModel sungguhan saat link
belum aktif. Yang salah cuma caranya — mengembalikan objek kosong tetap
membangun sesuatu, dan objek kosong itu tetap sampai ke layar.

Ada juga efek samping yang jarang disadari. `viewModel.flushData()` di cabang
yang sama memanggil `useCase.flushData()`, yang menjalankan
`repository = Repository()`. Kalau flush itu mengenai UseCase yang sungguhan,
repository jadi kosong, dan `setupView()` di cabang sebelahnya membacanya
beberapa milidetik kemudian. Urutan flush-lalu-setup ini tercetus tepat pada
interaksi yang sama — swipe back yang dibatalkan — jadi besar kemungkinan
blank screen dan field kosong yang intermiten itu adalah satu bug yang sama,
hanya berbeda seberapa cepat pemulihannya datang.

### Kenapa masalah ini hilang dengan sendirinya

`LazyNavigationLink` menghapus penyebabnya, bukan menambal gejalanya, sehingga
tambalannya tidak lagi dibutuhkan.

Builder hanya dipanggil sekali dan hasilnya disimpan. Saat body coordinator
dievaluasi ulang — karena swipe yang dibatalkan atau sebab lain —
`LazyNavigationDestination` yang baru dibuang oleh SwiftUI karena `@State`-nya
sudah terpasang, dan layar yang ter-push tetap memakai ViewModel yang sama
beserta datanya. Tidak ada evaluasi ulang, tidak ada objek kosong, tidak ada
blank.

Yang menjamin ini bukan sekadar hilangnya cabang `if`, tapi satu invarian:
**di kode yang baru tidak ada satu pun jalur yang menghasilkan ViewModel tanpa
konfigurasi.** `createDestination()` selalu membangun UseCase, ViewModel, dan
memanggil `loadData()` sebagai satu kesatuan. Kalau layar dapat ViewModel, ia
pasti ViewModel yang lengkap.

Invarian keduanya menutup sisi yang satu lagi: `setupView()` `private` dan
hanya bisa dipicu `onFetchSucceed`, sedangkan `onFetchSucceed` hanya menyala
dari dalam `loadData()` setelah repository terisi. Jadi `setupView()`
**mustahil** membaca repository kosong, apa pun yang terjadi pada `flushData()`
di siklus layar.

> Saat memigrasi halaman lain, cari tambalan sejenis. Cabang yang
> mengembalikan ViewModel kosong, pemanggilan `setupView()` atau `flushData()`
> dari coordinator, dan pemeriksaan `selection != named` di dalam pembangunan
> ViewModel semuanya adalah tanda masalah yang sama. Hapus tambalannya bersama
> penyebabnya, jangan hanya salah satu.

---

## Aturan

### 1. Coordinator tidak menyimpan ViewModel atau UseCase

Struct `View` di-init ulang setiap kali body induknya dievaluasi.
`private let viewModel = ...` berarti objek baru pada setiap render, bukan
sekali seumur layar.

```swift
// SALAH — objek baru pada setiap render
struct SomeCoordinator: View {
    @State private var useCase = SomeUseCase()
    private let viewModel = SomeViewModel()
}

// BENAR — tidak ada stored property; semua dibangun di dalam builder
struct SomeCoordinator: View {
    @Binding var selectionCoordinatorName: String?

    var body: some View {
        LazyNavigationLink(tag: Self.named, selection: $selectionCoordinatorName) {
            createDestination()
        }
    }
}
```

### 2. Bangun semuanya di dalam builder, jangan pernah di `body`

Builder `LazyNavigationLink` hanya jalan sekali, saat layar di-push. Objek
yang dibuat di sana belum diamati view mana pun, jadi mengonfigurasinya aman.
Mengonfigurasi objek yang **sudah** diamati dari dalam `body` tidak aman.

Pembedaannya bukan soal tempat menulis kode, tapi soal apakah ada view yang
sedang mengamati objek itu saat Anda mengubahnya.

### 3. Coordinator memanggil `loadData()`, tidak pernah `setupView()`

Satu jalur saja untuk mengisi tampilan: `loadData()` mengisi repository, lalu
callback `onFetchSucceed` menjalankan `setupView()`. Jadikan `setupView()`
`private` supaya aturan ini tidak bisa dilanggar tanpa sengaja.

```swift
viewModel.setUseCase(useCase)
viewModel.loadData()
```

Perlu diketahui apa yang **tidak** dijamin di sini. `startFetchSucceed(_:)`
mengirim `onFetchSucceed` lewat `DispatchQueue.main.async`, jadi `setupView()`
belum berjalan saat builder selesai. Frame pertama tetap merender field kosong,
dan frame berikutnya yang terisi — selisihnya satu frame, tidak terlihat mata.

Satu frame itu sengaja tidak dikejar. Menghilangkannya berarti memanggil
`setupView()` secara langsung dari jalur pembangunan, dan jalur kedua itulah
yang dulu memungkinkan `setupView()` membaca repository kosong. Satu jalur yang
konsisten lebih berharga daripada satu frame.

Yang dijamin justru ini: `setupView()` **mustahil** membaca repository kosong,
karena satu-satunya pemicunya adalah `onFetchSucceed`, dan `onFetchSucceed`
hanya menyala dari dalam `loadData()` setelah repository terisi.

### 4. ViewModel selalu membaca `repository`, tidak pernah `input`

`input` adalah apa yang diminta; `repository` adalah apa yang sudah
terselesaikan oleh `loadData()`. ViewModel yang membaca `input` akan tampak
benar padahal melewati satu langkah.

Ini konvensi, bukan kode. Menambahkan accessor khusus di tiap UseCase —
misalnya `var bankCard: BankCard { repository.bankCard }` — justru merusak
bentuk baku `input`/`repository`/`callback` dan tetap tidak mencegah siapa pun
membaca `input`. Aturan yang berlaku seragam di semua UseCase lebih berguna
daripada penjaga buatan di satu-dua tempat.

### 5. Satu gaya pembaruan sub-ViewModel

Pilih **assign ulang**, jangan campur dengan ubah-di-tempat. Assign ulang
selalu menerbitkan perubahan ke view; mengubah di tempat hanya sampai kalau
sub-ViewModel itu sendiri diamati. Mencampur keduanya dalam satu kelas
menghasilkan bug "nilainya berubah tapi layar tidak" yang sangat sulit
ditelusuri.

```swift
// Fungsi murni yang mengembalikan objek baru
private func makeCvvViewModel(_ bankCard: BankCard) -> DescriptionVerticalViewModel { ... }

private func setupView() {
    cvvViewModel = makeCvvViewModel(useCase.bankCard)
}
```

### 6. Closure yang disimpan selalu `[weak self]`

`useCase.callback.onFetchSucceed = setupView` menangkap `self` secara kuat.
Karena ViewModel menyimpan UseCase dan UseCase menyimpan closure itu, keduanya
saling menahan selamanya.

```swift
useCase.callback.onFetchSucceed = { [weak self] in self?.setupView() }
```

Di coordinator, tangkap **Binding sebagai nilai**, bukan struct View-nya:

```swift
private func makeDismissScreenHandler() -> () -> Void {
    let source = $sourceCoordinatorName
    return { source.wrappedValue = nil }
}
```

### 7. `renewIdentifier()` sekali per objek

Panggil saat UseCase dibuat, bukan pada setiap render. Memanggilnya saat
sebuah fetch berjalan akan membuat hasil fetch itu dibuang diam-diam.

### 8. Formatter di-cache

`DateFormatter()` termasuk operasi paling mahal di Foundation. Yang salah pada
kode lama bukan "bukan `static`", melainkan formatter dibuat sebagai variabel
lokal di dalam fungsi pengisian tampilan, sehingga lahir baru setiap fungsi itu
jalan. Ada tiga tingkat:

| Bentuk | Berapa kali dibuat |
|---|---|
| `let` lokal di dalam fungsi | setiap pemanggilan |
| `private let` property instance | sekali per ViewModel |
| `private static let` | sekali seumur aplikasi |

Naik ke property instance **sudah cukup** untuk soal biaya. Pilih `static`
hanya kalau dua syarat ini terpenuhi:

- Formatter tidak pernah diubah setelah dikonfigurasi. `DateFormatter` aman
  lintas thread selama hanya dibaca; menambah `formatter.dateFormat = ...` di
  titik pemakaian mengubahnya jadi data race lintas layar.
- Formatnya tetap, bukan teks yang mengikuti bahasa pengguna. Objek yang hidup
  seumur aplikasi mengunci `Locale.current` pada saat dibuat, jadi ia tidak
  ikut berubah kalau bahasa diganti dari dalam app.

Untuk format tetap, kunci locale-nya supaya setelan pengguna tidak mengubah
keluaran:

```swift
private static let monthAndYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = DateFormats.monthAndYear
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()
```

Untuk format yang harus mengikuti bahasa pengguna, pakai property instance
supaya ia dibangun ulang setiap layar dibuka.

### 10. UseCase tidak pernah menyentuh `callback` secara langsung

Helper di `UseCaseProtocol` — `startFetchLoading()`, `stopLoading()`,
`startFetchSucceed(_:)`, dan seterusnya — semuanya membungkus pemanggilan
callback dalam `DispatchQueue.main.async`. Itu memang tujuannya: callback
berujung pada penulisan `@Published`, dan `@Published` yang ditulis dari thread
selain main adalah perilaku tidak terdefinisi.

```swift
// SALAH — melewati jaminan main thread
callback.onStartFetchLoading()

// BENAR
startFetchLoading()
```

Selama `loadData()` kebetulan selalu dipanggil dari main thread, tidak ada yang
terlihat salah. Begitu satu UseCase memanggilnya dari hasil network, anomalinya
muncul — dan biasanya di layar yang sebenarnya tidak diubah apa-apa, sehingga
sangat sulit dihubungkan ke penyebabnya.

### 11. `renewIdentifier()` bukan formalitas

Ia bukan sekadar mengganti UUID; ia juga yang mengubah `state` menjadi
`.active`. UseCase tanpa itu akan menolak memuat data tanpa suara. Panggil
sekali saat UseCase dibuat, dan jangan pernah mengirim ViewModel yang membawa
UseCase default ke layar.

> Periksa juga helper yang menyembunyikan formatter di dalamnya. Ekstensi
> seperti `String.convertToDate(format:)` biasanya membuat `DateFormatter`
> baru pada setiap pemanggilan, dan biaya itu tidak terlihat dari titik
> pemakaian.

### 9. `@ObservedObject` tanpa nilai default

`@ObservedObject var viewModel = SomeViewModel()` membuat layar bisa dibangun
tanpa ViewModel dan tetap kompilasi — hasilnya layar kosong tanpa error.
Jadikan wajib, supaya kesalahannya tertangkap saat kompilasi.

---

## Checklist saat memigrasi layar lain

- [ ] Tidak ada stored property ViewModel/UseCase di struct coordinator
- [ ] Tidak ada cabang yang mengembalikan ViewModel kosong saat link belum aktif
- [ ] Coordinator tidak memanggil `flushData()` maupun `setupView()`
- [ ] Semua objek dibangun di dalam builder `LazyNavigationLink`
- [ ] `setupView()` sudah `private`, dan coordinator memanggil `loadData()`
- [ ] ViewModel membaca lewat satu akses tunggal di UseCase
- [ ] Semua sub-ViewModel di-assign ulang, tidak ada yang diubah di tempat
- [ ] Semua closure yang disimpan memakai `[weak self]` atau hanya menangkap nilai
- [ ] `renewIdentifier()` dipanggil tepat sekali, saat UseCase dibuat
- [ ] Tidak ada ViewModel yang sampai ke layar membawa UseCase default
- [ ] UseCase tidak memanggil `callback.onXxx()` langsung; selalu lewat helper
- [ ] Formatter berupa `static let`
- [ ] `@ObservedObject` di layar tidak punya nilai default
- [ ] Ada test yang memanggil `trackForMemoryLeaks` pada ViewModel dan UseCase
- [ ] Sudah lewat checkpoint navigasi (lihat [LIFECYCLE_RULES.md](LIFECYCLE_RULES.md))

---

## Cara memverifikasi perbaikannya

Bug ini intermiten, jadi "sudah dicoba dan muncul" bukan bukti. Yang
membuktikan adalah menghilangkan race-nya, dan itu bisa diperiksa langsung:

Pasang breakpoint di `setupView()` dan pastikan ia hanya terpanggil dari
callback UseCase, tidak pernah dari jalur `body`. Kalau stack trace-nya pernah
memuat evaluasi body, aturan 3 masih bocor di suatu tempat.

Lalu pastikan frame pertama sudah lengkap. Dengan `loadData()` dipanggil di
builder, repository sudah terisi sebelum view ada, sehingga field tidak pernah
melewati fase kosong sama sekali — tidak ada lagi render kedua yang perlu
ditunggu, dan tidak ada lagi yang bisa gagal datang.
