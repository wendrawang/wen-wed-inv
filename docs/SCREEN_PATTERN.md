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

**`renewIdentifier()` dipanggil pada setiap evaluasi body.** Kalau sebuah
fetch masih berjalan, identifier-nya berganti dan hasil fetch itu dibuang
tanpa suara — `onFetchSucceed` tidak pernah datang.

**`private let viewModel` pada struct View.** Struct di-init ulang setiap
render, jadi ViewModel beserta seluruh sub-ViewModel-nya kembali kosong, dan
apakah ia sempat terisi lagi sebelum frame berikutnya adalah soal waktu.

Ketiganya sensitif terhadap frekuensi render dan beban main thread. Itulah
kenapa hasilnya berbeda antar perangkat.

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
viewModel.loadData()   // repository terisi sebelum view pertama dirender
```

### 4. UseCase punya satu titik baca

`input` adalah apa yang diminta; `repository` adalah apa yang sudah
terselesaikan. ViewModel tidak boleh memilih sendiri di antara keduanya.

```swift
extension SomeUseCase {
    var bankCard: BankCard { repository.bankCard }
}
```

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

`DateFormatter()` termasuk operasi paling mahal di Foundation dan pengisian
tampilan bisa berjalan berkali-kali.

```swift
private static let monthAndYearFormatter: DateFormatter = { ... }()
```

### 9. `@ObservedObject` tanpa nilai default

`@ObservedObject var viewModel = SomeViewModel()` membuat layar bisa dibangun
tanpa ViewModel dan tetap kompilasi — hasilnya layar kosong tanpa error.
Jadikan wajib, supaya kesalahannya tertangkap saat kompilasi.

---

## Checklist saat memigrasi layar lain

- [ ] Tidak ada stored property ViewModel/UseCase di struct coordinator
- [ ] Semua objek dibangun di dalam builder `LazyNavigationLink`
- [ ] `setupView()` sudah `private`, dan coordinator memanggil `loadData()`
- [ ] ViewModel membaca lewat satu akses tunggal di UseCase
- [ ] Semua sub-ViewModel di-assign ulang, tidak ada yang diubah di tempat
- [ ] Semua closure yang disimpan memakai `[weak self]` atau hanya menangkap nilai
- [ ] `renewIdentifier()` hanya sekali, saat UseCase dibuat
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
