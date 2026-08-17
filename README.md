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
Sources/Navigation/LazyNavigationLink.swift  destination yang ditunda
Tests/Support/XCTestCase+MemoryLeak.swift  trackForMemoryLeaks
Examples/DetailCardInfo/                   layar rujukan, sudah diperbaiki
Examples/Base/UseCase.swift                penjagaan base yang berlaku global
docs/LIFECYCLE_RULES.md                    aturan lifecycle
docs/SCREEN_PATTERN.md                     pola layar + checklist migrasi
docs/BASE_VIEWMODEL_FINDINGS.md            temuan di ScreenContentViewModel
docs/SCREEN_CONTAINER_FINDINGS.md          temuan di Screen & ScreenContent
.swiftlint.yml                             aturan lifetime & performa render
.github/pull_request_template.md           checklist PR
.github/workflows/lint.yml                 penegakan di CI
```

`Examples/` adalah rujukan, bukan kode yang bisa dikompilasi berdiri sendiri —
ia menyebut tipe milik aplikasi (`Screen`, `UseCase`, `ScreenContentViewModel`,
`R.*`) yang tidak ada di repo ini, dan test-nya memakai `BankCard.stubbed()`
yang perlu Anda sediakan. Folder ini juga tidak ikut di-lint. Salin isinya ke
proyek, jangan di-build dari sini.

## Cara memakai

Untuk menulis atau memigrasi sebuah layar, baca
[docs/SCREEN_PATTERN.md](docs/SCREEN_PATTERN.md) — sembilan aturan beserta
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

Pencatatan dan pencetakan log sengaja dipisah. Counter selalu jalan, konsol
default-nya diam:

```swift
#if DEBUG
LifecycleTracker.shared.loggingPolicy = .none                    // sehari-hari
LifecycleTracker.shared.loggingPolicy = .matching(["DebitCard"]) // saat audit
#endif
```

Jadi memasang probe di sebuah class tidak pernah membanjiri konsol orang lain,
sementara checkpoint tetap punya data yang akurat.

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
