# Temuan di `ScreenContentViewModel`

> **Sumbernya versi lama.** Analisis ini dibuat terhadap `ScreenContentViewModel`
> **sebelum** perbaikan yang membuat `deinit` mulai terpanggil. Sebagian temuan
> di bawah mungkin sudah tertutup. Jangan pakai dokumen ini sebagai daftar
> pekerjaan — pakai sebagai daftar hal yang perlu dipastikan, dan biarkan test
> yang memutuskan. `testScreenViewModelIsReleasedAfterInit` menjawab temuan 1
> tanpa perlu membandingkan versi sama sekali.

Semua yang ada di sini berlaku untuk **setiap layar** di aplikasi, karena
letaknya di base class. Perbaikan di sini menyebar ke ratusan halaman tanpa
menyentuh satu pun file layar — daya ungkitnya jauh lebih besar daripada
memigrasi halaman satu per satu.

Diurutkan berdasarkan dampak.

---

## 1. Setiap ViewModel layar punya retain cycle sejak `init()`

Ini yang paling serius. `init()` memanggil dua fungsi, dan keduanya memasang
closure yang menahan `self` secara kuat:

```swift
init() {
    setupNetworkObserver()
    setupImagePickerViewModel()
    setupPrimitiveAddContactFormViewModel()
}

func setupImagePickerViewModel() {
    primitiveImagePickerViewModel.didChange = receiveImageFromPicker
}

func setupPrimitiveAddContactFormViewModel() {
    primitiveAddContactFormViewModel.onContactAdded = didAddContactSucceed
    primitiveAddContactFormViewModel.onCanceled = dismissBottomSheet
}
```

Menulis nama method tanpa tanda kurung menghasilkan closure yang menangkap
`self` kuat — bentuknya bersih tetapi efeknya identik dengan
`{ self.receiveImageFromPicker(...) }`. Dan karena
`primitiveImagePickerViewModel` serta `primitiveAddContactFormViewModel`
adalah property milik `self`, lingkarannya tertutup:

```
self → primitiveImagePickerViewModel → didChange → self
```

Pola yang sama muncul di dua tempat lain:

```swift
bottomSheetWebViewModel.didWebViewHeightChanged = setupBottomSheetMaxHeight
messageComposerViewModel.completion = didReceiveMessageComposeResult
```

Yang dua terakhir hanya terpasang saat fitur terkait dipakai; yang di `init()`
terpasang pada **setiap ViewModel layar yang pernah dibuat**.

### Perbaikan

```swift
func setupImagePickerViewModel() {
    primitiveImagePickerViewModel.didChange = { [weak self] image, named in
        self?.receiveImageFromPicker(image: image, named: named)
    }
}

func setupPrimitiveAddContactFormViewModel() {
    primitiveAddContactFormViewModel.onContactAdded = { [weak self] in
        self?.didAddContactSucceed()
    }

    primitiveAddContactFormViewModel.onCanceled = { [weak self] in
        self?.dismissBottomSheet()
    }
}

private func setupBottomSheetWebViewModel(...) {
    bottomSheetWebViewModel.didWebViewHeightChanged = { [weak self] in
        self?.setupBottomSheetMaxHeight()
    }
}

func showMessageComposer(recipients: [String], body: String) {
    messageComposerViewModel.completion = { [weak self] result in
        self?.didReceiveMessageComposeResult(result: result)
    }
}
```

### Cara memastikan

Satu test, tanpa persiapan apa pun. Kalau `init()` memang membuat lingkaran,
test ini merah tanpa perlu menjalankan skenario apa pun:

```swift
func testScreenViewModelIsReleasedAfterInit() {
    let sut = DetailCardInfoScreenViewModel()
    trackForMemoryLeaks(sut)
}
```

Jalankan ini dulu sebelum menyentuh apa pun. Hasilnya menentukan apakah
temuan ini nyata di build Anda atau tidak — analisis kode bisa saja meleset
kalau ada detail di tipe anak yang belum saya lihat.

---

## 2. Ukuran scroll di `@Published` kemungkinan besar penyebab fps turun

```swift
@Published var scrollViewContainerSize: CGSize = .zero
@Published var scrollViewContentSize: CGSize = .zero
```

`ObservableObject` invalidasinya **object-level**: satu `@Published` berubah,
seluruh body layar dievaluasi ulang. Dan `@Published` menerbitkan perubahan
pada **setiap penulisan**, tanpa membandingkan nilai lama — menulis `CGSize`
yang sama persis tetap memicu invalidasi penuh.

Kalau kedua property ini diisi dari `GeometryReader` atau `PreferenceKey` di
dalam pembungkus scroll — dan bentuknya sangat mengarah ke sana — maka setiap
frame scroll menerbitkan satu sampai dua invalidasi seluruh layar. Pada 120Hz
itu 240 evaluasi body per detik untuk nilai yang sebagian besar tidak berubah.

Ini kandidat terkuat untuk pertanyaan "kenapa fps tidak stabil", dan letaknya
di base class, jadi berlaku di semua layar yang bisa di-scroll.

### Perbaikan

Kode Anda sudah memakai pola penjagaan ini di tempat lain:

```swift
func setUserInteractionEnabled(_ enabled: Bool = true) {
    if isUserInteractionEnabled == enabled {
        return
    }
    ...
}
```

Yang dibutuhkan sama, hanya tidak bisa lewat `didSet` — `@Published`
menerbitkan di `willSet`, jadi saat `didSet` berjalan invalidasinya sudah
terlanjur. Perlu penerbitan manual:

```swift
private var storedScrollViewContentSize: CGSize = .zero

var scrollViewContentSize: CGSize {
    get { storedScrollViewContentSize }
    set {
        guard newValue != storedScrollViewContentSize else { return }
        objectWillChange.send()
        storedScrollViewContentSize = newValue
    }
}
```

Sama untuk `scrollViewContainerSize`. Setelah ini, ukuran hanya menerbitkan
saat layout benar-benar berubah, bukan pada setiap frame.

**Ukur dulu sebelum dan sesudah.** Instruments dengan template SwiftUI, kolom
View Body, sambil men-scroll layar terpanjang Anda di build Release. Kalau
jumlah body evaluation turun drastis, temuan ini terkonfirmasi; kalau tidak,
penyebabnya di tempat lain dan sebaiknya jangan lanjut menebak.

### Pertimbangkan juga memindahkannya keluar

Ukuran scroll adalah urusan lapisan view, bukan state layar. Menyimpannya di
`ObservableObject` yang sama dengan data layar berarti gerakan visual dan
perubahan data berbagi satu saluran invalidasi. Kalau nanti ada kesempatan,
memindahkannya ke `@State` di view lebih tepat secara arsitektur.

---

## 3. Layar yang sudah ditinggalkan ikut memuat ulang data

```swift
@objc func didNetworkAvailable() {
    if networkUnavailableNavigationViewModel.isReceiveError {
        loadData()
    }
    networkUnavailableNavigationViewModel.dismiss()
}
```

`didNetworkUnavailable` dijaga oleh `isPresenting`, tetapi `didNetworkAvailable`
tidak. Padahal setiap `ScreenContentViewModel` yang masih hidup terdaftar
sebagai observer.

Ini bertemu dengan sifat pelepasan tertunda yang sudah kita ukur: layar yang
sudah di-pop belum tentu sudah dilepas. Saat koneksi kembali, semua ViewModel
yang masih tersisa di memori dan pernah menerima error jaringan akan
menjalankan `loadData()` bersamaan — request untuk layar yang tidak terlihat,
di main thread, tepat saat pengguna sedang menunggu layar yang sekarang.

### Perbaikan

```swift
@objc func didNetworkAvailable() {
    networkUnavailableNavigationViewModel.dismiss()

    guard isPresenting else { return }

    if networkUnavailableNavigationViewModel.isReceiveError {
        loadData()
    }
}
```

Catatan: observer-nya sendiri **bukan** kebocoran. Sejak iOS 9,
`NotificationCenter` menyimpan observer bergaya selector sebagai referensi
weak yang otomatis nol, jadi tidak ada `removeObserver` yang hilang di sini.
Masalahnya murni soal siapa yang boleh bereaksi.

---

## 4. `AnyView` ada di body setiap layar

```swift
var onCreateNavigationLinks: () -> AnyView = { DefaultValues.emptyAnyView }
```

Setiap layar memanggil ini dari `body` lewat `renderNavigationLinks()`.
`AnyView` menghapus structural identity, sehingga SwiftUI kehilangan jalur
diff murahnya untuk seluruh subtree navigasi — di semua layar sekaligus.

Ini tidak bisa diperbaiki dengan penggantian satu baris karena tipenya harus
tetap seragam untuk semua layar. Yang realistis: jadikan bagian dari keputusan
navigasi yang masih menggantung. Kalau coordinator pindah ke
`UINavigationController`, kebutuhan `onCreateNavigationLinks` hilang sama
sekali dan `AnyView` ini ikut hilang tanpa pekerjaan tambahan.

Sementara itu, dampaknya bergantung pada seberapa sering body layar
dievaluasi — yang membawa kita kembali ke temuan 2. Perbaiki itu dulu, lalu
ukur ulang.

---

## Urutan yang saya sarankan

1. Jalankan `testScreenViewModelIsReleasedAfterInit`. Ini menentukan temuan 1
   nyata atau tidak, dan biayanya satu file test.
2. Kalau merah, pasang `[weak self]` di lima titik itu. Perbaikan terbesar
   dengan perubahan terkecil di seluruh percakapan ini.
3. Ukur body evaluation saat scroll dengan Instruments, lalu pasang penjagaan
   nilai pada dua ukuran scroll, lalu ukur lagi.
4. Tambahkan penjagaan `isPresenting` pada `didNetworkAvailable`.

Tiga yang pertama tidak menyentuh satu pun file layar.
