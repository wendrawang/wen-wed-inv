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

## Perbaikannya sudah ditulis, menunggu verifikasi di aplikasi

| Temuan | Catatan |
|---|---|
| `Screen` membuang satu `ScreenContentViewModel` lengkap per konstruksi | Nilai default `@ObservedObject` selalu ditimpa oleh `content.viewModel`. Objek yang dibuang membawa 20-an `@Published` dan dua pendaftaran `NotificationCenter`. Perbaikannya di [`Examples/Base/Screen.swift`](../Examples/Base/Screen.swift); cara mengukurnya di bawah |

### Cara memverifikasi perbaikan `Screen`

Objek yang dibuang adalah `ScreenContentViewModel` **base**, bukan subclass
layar, jadi probe di ViewModel layar tidak akan melihatnya. Pengukurannya
sekali jalan lalu dibongkar lagi:

1. Pasang `LifecycleProbe` sementara di `ScreenContentViewModel` base.
2. Buka satu layar, catat berapa `INIT ScreenContentViewModel` muncul.
3. Pasang perbaikannya, buka layar yang sama, catat lagi.
4. Lepas probe-nya.

Sebelum perbaikan jumlahnya dua per layar — satu dibuang, satu dipakai.
Sesudahnya satu.

---

## Masih dugaan — butuh pengukuran sebelum disentuh

Prosedur lengkapnya di [MEASUREMENT_GUIDE.md](MEASUREMENT_GUIDE.md).

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
| `renewIdentifier()` yang dipanggil berulang membuang hasil fetch yang sedang berjalan | **Nyata di Transfer Landing** — `loadData(pageNumber:searchKeyword:)` memanggil jaringan sungguhan. Detail Card Info sinkron sehingga tidak terkena |
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

## Layar berikutnya: Transfer Landing

Analisis lengkapnya di [TRANSFER_LANDING_FINDINGS.md](TRANSFER_LANDING_FINDINGS.md).
Enam temuan, tiga di antaranya tidak muncul di layar pendek:

| Temuan | Status |
|---|---|
| `@Published` array di-`append` per baris — satu penerbitan per kontak | Terbukti dari kode; kandidat terkuat untuk fps di layar ini |
| `.id(destinationCoordinatorName)` merobohkan seluruh layar tiap navigasi | Terbukti dari kode; terikat keputusan navigasi |
| Sepuluh retain cycle, dua di antaranya per baris list | Terbukti dari kode; butuh test untuk memastikan |
| Kamus sembilan closure dibangun ulang tiap render | Terbukti dari kode |
| Kamus closure sebagai lazy navigation | **Sudah benar** — hanya satu tujuan yang dibangun |

---

## Belum pernah dilihat

Satu hal yang paling menentukan untuk fps dan memori masih belum terbaca:
**view yang mengubah `url` menjadi piksel.** `ImageViewModel` hanya menyimpan
string — tidak ada unduhan, cache, decode, maupun downsampling di dalamnya.
Selama itu belum terlihat, pertanyaan "apa penyebab terbesar fps turun" belum
punya jawaban lengkap.
