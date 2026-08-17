# Template iOS — MVVM + Coordinator

Template untuk aplikasi SwiftUI dengan target minimum **iOS 13**, arsitektur
MVVM + Coordinator.

Isinya saat ini adalah bagian yang **tidak bergantung pada keputusan
navigasi** — perkakas lifecycle, penegakan lewat test dan lint, serta
dokumentasi aturannya. Bagian navigasi dan DI menyusul setelah keputusan di
bawah diambil.

## Isi

```
Sources/Debug/LifecycleProbe.swift         probe opt-in per class
Sources/Debug/LifecycleTracker.swift       counter + checkpoint
Sources/Debug/RenderCounter.swift          penghitung evaluasi body (sementara)
Sources/Navigation/LazyNavigationLink.swift  destination yang ditunda
Tests/Support/XCTestCase+MemoryLeak.swift  trackForMemoryLeaks
Examples/DetailCardInfo/                   layar rujukan pendek, sudah diperbaiki
Examples/TransferLanding/                  layar panjang berlist, perbaikan minimal
Examples/Base/UseCase.swift                penjagaan base yang berlaku global
Examples/Base/Screen.swift                 tanpa ScreenContentViewModel terbuang
docs/STATUS.md                             status semua temuan
docs/MEASUREMENT_GUIDE.md                  cara mengukur dengan Instruments
docs/LIFECYCLE_RULES.md                    aturan lifecycle
docs/ACCESS_MATRIX.md                      matriks akses antar lapisan
docs/SCREEN_PATTERN.md                     pola layar + checklist migrasi
docs/BASE_VIEWMODEL_FINDINGS.md            temuan di ScreenContentViewModel
docs/SCREEN_CONTAINER_FINDINGS.md          temuan di Screen & ScreenContent
docs/TRANSFER_LANDING_FINDINGS.md          temuan di layar panjang berlist
.swiftlint.yml                             aturan lifetime & performa render
.github/pull_request_template.md           checklist PR
.github/workflows/lint.yml                 penegakan di CI
```

`Examples/` adalah rujukan, bukan kode yang bisa dikompilasi berdiri sendiri —
ia menyebut tipe milik aplikasi (`Screen`, `UseCase`, `ScreenContentViewModel`,
`R.*`) yang tidak ada di repo ini. Folder ini juga tidak ikut di-lint. Salin
isinya ke proyek, jangan di-build dari sini.

Dua bagian yang perlu Anda sunting setelah menyalin. `stubbedForCardInfoTests()`
di bagian bawah `DetailCardInfoScreenViewModelTests.swift` — bentuknya tebakan
dari pemakaian `BankCard(.unspecified)`, jadi sesuaikan dengan inisialiser
sebenarnya. Dan dua test terakhir di `TransferLandingViewModelTests.swift`
membutuhkan `RecipientService` yang di-stub. Test lainnya berjalan apa adanya.

## Cara memakai

Untuk menulis atau memigrasi sebuah layar, baca
[docs/SCREEN_PATTERN.md](docs/SCREEN_PATTERN.md) — sebelas aturan beserta
checklist migrasi, diturunkan dari satu bug nyata di layar Detail Debit Card
Info (CVV dan nomor kartu kadang kosong).

Untuk aturan lifecycle-nya, baca
[docs/LIFECYCLE_RULES.md](docs/LIFECYCLE_RULES.md). Ringkasnya, ada tiga
lapis dan hanya lapis pertama yang wajib untuk semua perubahan:

1. **Test yang gagal** — `trackForMemoryLeaks` di setiap test yang membuat
   ViewModel, UseCase, atau Coordinator. Ini yang merahkan CI.
2. **Probe lifecycle** — opt-in per class, dipasang saat mengaudit sebuah
   flow atau saat kebetulan menyentuh file tersebut.
3. **Checkpoint navigasi** — masuk ke layar terdalam, kembali ke root, pastikan
   tidak ada objek berumur layar yang tersisa.

Probe bersifat opt-in per class, jadi yang tercetak hanya tipe yang sengaja
Anda pasangi probe. Karena itu default-nya `.all` — memasang probe langsung
terlihat hasilnya, tanpa konfigurasi apa pun.

Kalau nanti probe sudah terpasang di banyak tempat dan konsolnya jadi ramai,
saring atau matikan di `AppDelegate`:

```swift
#if DEBUG
LifecycleTracker.shared.loggingPolicy = .matching(["DebitCard"])
LifecycleTracker.shared.loggingPolicy = .none
#endif
```

Counter tetap akurat apa pun pilihannya, jadi checkpoint tidak terpengaruh.

### Kalau log tidak muncul

Urut dari yang paling sering: build-nya Release (seluruh file probe ada di
dalam `#if DEBUG`), class-nya belum dipasangi `LifecycleProbe`, atau
`loggingPolicy` diturunkan di suatu tempat. Log memakai `os_log` level `.info`
dengan kategori `ObjectLifecycle` — di konsol Xcode langsung terlihat, di
Console.app saring dengan subsystem bundle identifier aplikasi.

## Status temuan

Penelusuran ini menghasilkan belasan temuan dengan tingkat kepastian berbeda.
[docs/STATUS.md](docs/STATUS.md) memisahkan mana yang sudah terbukti, mana yang
masih dugaan dan butuh pengukuran, dan mana yang sudah dicoret — baca itu dulu
sebelum mengerjakan apa pun dari dokumen temuan.

Untuk yang masih dugaan, [docs/MEASUREMENT_GUIDE.md](docs/MEASUREMENT_GUIDE.md)
berisi cara mengukurnya: empat pengukuran, apa yang dibaca dari masing-masing,
dan urutan yang paling hemat waktu.

## Prinsip yang mendasarinya

**Kepemilikan lebih menentukan daripada `weak`.** Setiap objek punya tepat satu
pemilik; referensi balik ke pemilik yang `weak`. Menaburkan `weak` di mana-mana
menukar kebocoran dengan crash, dan crash lebih sulit didiagnosis.

**Closure yang disimpan selalu `[weak self]`.** Kalau objek A menyimpan closure
dan closure itu menyebut objek yang memiliki A, closure itu butuh `[weak self]`.
Closure yang langsung dieksekusi (`map`, `filter`, `sort`) tidak perlu apa-apa.
Perlu diingat `useCase.callback.onDone = handleDone` — menulis nama method tanpa
tanda kurung — juga menangkap `self` secara kuat.

**`body` harus murni.** Tidak ada efek samping, tidak ada mutasi state, tidak
ada kerja berat. `body` bisa dievaluasi puluhan kali per detik.

**Aturan harus menggagalkan sesuatu.** Log yang harus dibaca manusia akan luput
dalam dua minggu.

## Keputusan yang masih menggantung

Empat hal ini menentukan bentuk sisa template:

1. **Navigasi** — `NavigationView` + `LazyNavigationLink`, atau
   `UINavigationController` + `UIHostingController`. Yang kedua memberi
   `popToRoot` dan deeplink yang deterministik serta lifetime ViewModel yang
   jelas; yang pertama jauh lebih murah diadopsi. Keduanya bisa berdampingan
   per flow.
2. **Concurrency** — `async/await` (bisa di-back-deploy ke iOS 13 sejak
   Xcode 13.2, dengan runtime concurrency ikut di bundle) atau Combine murni.
3. **DI** — container manual berbasis protocol factory, atau library seperti
   Swinject/Resolver.
4. **Skala** — jumlah layar, dan ada tidaknya flow dengan list panjang atau
   media berat yang butuh bungkus `UICollectionView`.
