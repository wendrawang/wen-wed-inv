# Status Temuan

Selama penelusuran ini terkumpul belasan temuan dengan tingkat kepastian yang
berbeda-beda. Dokumen ini memisahkan mana yang **sudah terbukti**, mana yang
**masih dugaan**, dan mana yang **sudah dicoret** — supaya tidak ada yang
mengerjakan hipotesis seolah-olah itu bug.

Terakhir diperbarui setelah verifikasi di aplikasi: seluruh unit test hijau,
dan skenario background/foreground, notifikasi, serta snackbar berjalan aman.

---

## Selesai dan terverifikasi

| Temuan | Bukti |
|---|---|
| `setupView()` membaca `repository` sebelum `loadData()` mengisinya | Test `testFieldsArePopulatedAfterLoadData` hijau; layar terisi benar di aplikasi |
| `setupView()` menulis `@Published` di tengah evaluasi `body` | `setupView()` sekarang `private`, hanya bisa dipicu `onFetchSucceed` |
| `private let viewModel` pada struct View dibuat ulang tiap render | Log lifecycle: konstruksi terjadi **tepat sekali** saat layar dibuka |
| Cabang yang mengembalikan ViewModel kosong → layar blank | Cabangnya hilang; skenario re-render (background, snackbar, notif) tidak lagi berkedip |
| `state == .inactive` menyebabkan kegagalan senyap | `assertionFailure` di base `UseCase` |
| Retain cycle di `ScreenContentViewModel.init()` | **Dicoret.** `testScreenViewModelIsReleasedAfterInit` hijau — sudah tertutup perbaikan sebelumnya |
| ViewModel membuang satu UseCase default per konstruksi | Terlihat di log; ditutup dengan `lazy` |

---

## Terbukti dari kode, perbaikannya belum dipasang

| Temuan | Catatan |
|---|---|
| `Screen` membuang satu `ScreenContentViewModel` lengkap per konstruksi | Nilai default `@ObservedObject` selalu ditimpa oleh `content.viewModel`. Objek yang dibuang membawa 20-an `@Published` dan dua pendaftaran `NotificationCenter`. Perbaikannya ada di [SCREEN_CONTAINER_FINDINGS.md](SCREEN_CONTAINER_FINDINGS.md) temuan 2 |

---

## Masih dugaan — butuh pengukuran sebelum disentuh

| Dugaan | Cara memastikan |
|---|---|
| `scrollViewContainerSize` / `scrollViewContentSize` sebagai `@Published` adalah penyebab fps tidak stabil | Instruments template SwiftUI, kolom View Body, scroll layar terpanjang di build **Release** |
| `.blur()` di akar setiap layar memicu offscreen rendering walau radiusnya nol | Instruments Core Animation, centang Color Offscreen-Rendered |
| `AppState` sebagai `@EnvironmentObject` di setiap `Screen` jadi saluran invalidasi global | Cek seberapa sering `AppState` benar-benar berubah |
| `onAppear` menyala lebih dari sekali sehingga layar berbasis network memuat ganda | Pasang probe pada UseCase layar yang memanggil network, lalu navigasi maju-mundur |
| `didNetworkAvailable()` tanpa penjagaan `isPresenting` membuat layar yang sudah ditinggalkan memuat ulang | Matikan koneksi di layar dalam, kembali ke root, nyalakan lagi, perhatikan log |

---

## Berlaku umum, bukan bug di layar ini

| Catatan | Kapan menggigit |
|---|---|
| `renewIdentifier()` yang dipanggil berulang membuang hasil fetch yang sedang berjalan | Hanya untuk UseCase yang benar-benar asinkron. Layar ini sinkron, jadi tidak terkena |
| Memanggil `callback.onXxx()` langsung melewati jaminan main thread | Setiap UseCase yang `loadData()`-nya bisa berjalan di luar main thread |
| Mengganti sub-ViewModel yang memiliki sumber daya (gambar, web view) memicu muat ulang | Layar yang menaruh `ImageViewModel` di sub-ViewModel yang di-refresh |
| `onCreateNavigationLinks` bertipe `AnyView` ada di body setiap layar | Hilang sendiri kalau navigasi pindah ke `UINavigationController` |

---

## Sudah dicoret

| Dugaan yang salah | Kenyataannya |
|---|---|
| `.setHidden` menyisakan view di hierarki | `isRemove: true` default benar-benar mengeluarkannya lewat cabang ViewBuilder |
| `renderSheetView()` membangun enam representable sekaligus | Hanya yang cocok dengan `sheetState` yang dibangun |
| `PrimitiveAddContactForm` dibangun di semua layar | Hanya `init` struct-nya sebagai argumen, dan itu murah |
| Observer `NotificationCenter` bocor karena tidak pernah di-remove | Sejak iOS 9 observer bergaya selector disimpan weak dan otomatis nol |
| Frame pertama sudah lengkap setelah `loadData()` di builder | `startFetchSucceed(_:)` asinkron, jadi selalu ada selisih satu frame |
| Coordinator perlu memanggil `loadData()` | `Screen.onAppear` sudah melakukannya; memanggil lagi berarti muat ganda |

---

## Belum pernah dilihat

Satu hal yang paling menentukan untuk fps dan memori masih belum terbaca:
**view yang mengubah `url` menjadi piksel.** `ImageViewModel` hanya menyimpan
string — tidak ada unduhan, cache, decode, maupun downsampling di dalamnya.
Selama itu belum terlihat, pertanyaan "apa penyebab terbesar fps turun" belum
punya jawaban lengkap.
