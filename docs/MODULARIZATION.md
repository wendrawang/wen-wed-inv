# Memecah ke local SPM

Rencana untuk kondisi Anda: **networking tetap di project yang ada**, yang
dipindah ke package hanya navigasi dan flow fitur baru — supaya flow lama tidak
tersenggol sama sekali, sekaligus persiapan revamp.

---

## Mulai dari mana

Bukan dari yang paling kecil — dari yang **tidak bergantung pada apa pun**.

Ukuran dan kesulitan sering tidak sejalan. `DefaultValues` mungkin ratusan
baris tetapi isinya konstanta murni, jadi memindahkannya nol risiko. Satu file
tiga puluh baris yang menyebut `R.string` justru menyeret seluruh persoalan
resource. Yang menentukan arah dependensinya, bukan jumlah barisnya.

Aturannya: **pindahkan daun lebih dulu.** Sesuatu layak jadi langkah berikutnya
kalau, setelah dipindah, package-nya masih bisa dikompilasi tanpa menyebut satu
pun tipe yang tinggal di project.

### Apa yang disebut "aman" di sini

Sebuah langkah aman kalau ketiganya terpenuhi:

1. **Tidak mungkin mengubah perilaku.** Yang dipindah nilai, tipe, atau fungsi
   murni — bukan sesuatu yang punya state atau urutan.
2. **Kompiler yang memverifikasi.** Kalau ada yang terlewat, build gagal. Bukan
   sesuatu yang baru ketahuan saat dijalankan.
3. **Bisa dibatalkan dalam satu commit.** Tidak ada langkah yang menuntut
   langkah berikutnya untuk bisa dikompilasi.

Lapis 4 (`Screen`, `ScreenContentViewModel`) gagal di ketiganya. Karena itu ia
terakhir, bukan karena ia besar.

### Tiga langkah pertama

**Langkah 0 — jangan memecah dulu.** Buktikan flow transfer jalan di aplikasi:
daftar muncul, tab dan pencarian bekerja, back kembali ke Dashboard, dan probe
mencetak INIT/DEINIT berpasangan. Memecah lebih dulu hanya menambah satu
variabel saat ada yang tidak beres — dan akan ada yang tidak beres.

**Langkah 1 — `FlowKit`.** Isinya `Sources/Navigation` dan `Sources/Debug`.
Satu-satunya keputusan: `.invisible()` di `LazyNavigationLink` ikut dibawa, atau
diganti padanan di dalam package.

Yang perlu `public` sedikit, dan bisa didaftar:

| `public` | Dipakai project untuk |
|---|---|
| `AppRouter`, `PendingFlow`, `View.mountFlowRouter()` | membuka flow |
| `FlowNavigator` beserta method-nya | dipegang coordinator |
| `LazyNavigationLink` | layar yang masih `NavigationView` |
| `LifecycleProbe`, `LifecycleTracker`, `RenderCounter` | probe dan pengukuran |
| `PropertyBindable` | `useCase.binding(\.output.x)` |

Sisanya biarkan internal — `FlowPresenter`, `FlowNavigationController`, dan
`FlowStepHostingController` hanya dipakai dari dalam package. Kalau ada yang
ternyata dibutuhkan project, kompiler yang memberi tahu.

`trackForMemoryLeaks` masuk target test terpisah (`.testTarget`), bukan target
utama.

Selesai kalau: project build, flow transfer masih jalan, dan tidak ada satu
baris pun flow lama yang berubah.

**Langkah 2 — Lapis 1 saja.** Token, `TypeAliases`, extension `UIApplication`,
konstanta. Semuanya daun, semuanya diverifikasi kompiler.

Lalu **berhenti dan nilai ulang.** Dua langkah itu sudah memberi manfaat nyata
dan tidak menuntut langkah ketiga. Lapis 2–4 baru masuk akal saat revamp benar
benar dimulai, bukan sebelumnya.

---

## Batasan yang menentukan segalanya

**Package tidak bisa mengimpor App target.** Arahnya selalu satu:
App → Package. Jadi apa pun yang masuk package tidak boleh menyebut satu pun
tipe yang tinggal di project.

Itu terdengar sepele sampai dihitung. Ini yang disebut layar transfer kita hari
ini, semuanya milik project:

| Tipe | Muncul | Jenis |
|---|---|---|
| `Spaces`, `IconSizes`, `Currencies` | 21× | design token |
| `DefaultValues` | 13× | konstanta |
| `R.string`, `R.image` | 12× | resource |
| `AnalyticManager` | 6× | layanan |
| `Screen`, `ScreenContentViewModel`, `PaginationScreenContentViewModel` | 7× | base UI |
| `AutomationIdentifierManager`, `DialogCodes`, `TypeAliases` | 5× | lain-lain |

Selama itu semua di project, **layar transfer yang ada tidak bisa pindah ke
package** — dan memaksakannya berarti menyeret hampir seluruh base UI ikut
pindah, yang justru menyenggol semua flow lama. Kebalikan dari yang Anda mau.

---

## Karena itu: dua tahap, bukan satu

### Tahap 1 — sekarang: satu package, dan itu saja

```
Packages/
  FlowKit/                    ← Sources/Navigation + Sources/Debug
```

`FlowKit` sudah siap hari ini. Seluruh `Sources/` hanya mengimpor `SwiftUI`,
`UIKit`, `Foundation`, dan `os.log`. Satu-satunya yang menyebut tipe project
adalah `.invisible()` di `LazyNavigationLink` — sudah ditandai di kodenya, dan
pilihannya dua: bawa modifier-nya ikut ke package, atau ganti dengan padanan di
dalam package.

Yang **tetap di project**: seluruh networking, `TransferFlowCoordinator`,
`TransferLandingFactory`, dan semua layarnya. Flow coordinator itu satu file dan
tidak masalah tinggal di project — ia memakai `FlowKit`, bukan sebaliknya.

Hasil tahap ini sudah nyata: flow baru dibangun di atas package yang dependensinya
nol, dan tidak ada satu baris pun flow lama yang tersentuh.

### Tahap 2 — saat revamp: fitur baru lahir langsung sebagai package

Fitur **baru** tidak punya utang ke base UI lama, jadi ia bisa berdiri sebagai
package sejak hari pertama:

```
Packages/
  FlowKit/                    navigasi + lifecycle
  UIKitchen/                  Screen baru, token, komponen — untuk fitur baru
  PaymentFeature/             fitur revamp pertama
```

Fitur lama pindah belakangan, satu per satu, saat base UI-nya sudah punya
padanan di `UIKitchen`. Tidak ada momen "pindah semua sekaligus".

---

## Kalau tipe-tipe itu memang mau dipindah ke Core

Bisa, tapi biayanya sangat berbeda per tipe. Kalau diurutkan dari yang paling
murah, urutannya juga jadi urutan mengerjakannya — karena yang di bawah
bergantung pada yang di atas.

### Lapis 1 — pindah apa adanya, nol risiko

`Spaces`, `IconSizes`, `Currencies`, `TypeAliases`, `UIApplication.endEditing()`,
dan sebagian besar `DefaultValues`.

Semuanya nilai murni atau extension tanpa dependensi. Pindahkan, tambahkan
`public`, selesai. Ini separuh dari 21 + 13 pemakaian yang kita hitung tadi, dan
tidak ada satu pun yang bisa salah.

Satu catatan kecil: `DefaultValues.emptyAnyView` butuh `import SwiftUI`, jadi
taruh di target UI, bukan di target Foundation.

### Lapis 2 — layanan: protokol di Core, implementasi tetap di project

`AnalyticManager`, `AutomationIdentifierManager`.

Keduanya singleton dengan katalog besar — daftar event, daftar identifier — dan
katalog itu tumbuh mengikuti fitur. Memindahkan katalognya berarti Core ikut
tahu setiap fitur, dan itu arah yang salah.

Polanya sama dengan networking:

```swift
// Core — hanya bentuknya
public protocol AnalyticTracking {
    func track(_ event: AnalyticEvent)
}

// project — katalognya tetap di sini
extension AnalyticManager: AnalyticTracking {}
```

Layar berhenti menulis `AnalyticManager.instance.analytics.visitTransferLanding`
dan menerima event-nya dari luar. Itu memang refactor, tetapi bertahap: yang
belum disentuh tetap memakai singleton-nya.

`AutomationIdentifierManager` sebetulnya cuma kumpulan `String` tanpa
dependensi, jadi kalau mau, ia boleh ikut Lapis 1 apa adanya.

### Lapis 3 — resource

`R.string`, `R.image`, dan `DialogCodes` yang isinya menyebut `R.string`.
Bagian tersendiri di bawah.

### Lapis 4 — base UI, dan ini pekerjaan yang sebenarnya

`Screen`, `ScreenContentViewModel`, `PaginationScreenContentViewModel`.

Sengaja ditaruh terakhir, karena ketiganya menyebut **semua** yang di atas —
token, resource, analytic, snackbar, `AppState`. Memindahkannya lebih dulu
berarti menyeret semuanya sekaligus, dan di situlah flow lama mulai tersenggol.

Kalau Lapis 1–3 sudah beres, lapis ini jadi pekerjaan mekanis. Kalau belum, ia
jadi proyek tersendiri.

---

## `R.swift` di local SPM

### Cara kerjanya

SPM punya dukungan resource sejak Swift 5.3. Target yang membawa resource
mendeklarasikannya di `Package.swift`:

```swift
.target(
    name: "CoreUI",
    resources: [.process("Resources")]
)
```

Isinya diakses lewat `Bundle.module` — konstanta yang dibuatkan SPM otomatis
untuk setiap target yang punya resource.

`R.swift` sendiri menyediakan SwiftPM build tool plugin sejak versi 7. **Pastikan
versi yang Anda pakai sebelum merencanakan** — kalau proyek Anda masih di versi
lama, plugin-nya belum ada dan jalurnya berbeda.

### Yang berubah: `R` menjadi per-module

Ini konsekuensi yang paling sering mengejutkan. `R` yang dihasilkan di `CoreUI`
adalah tipe yang **berbeda** dari `R` di project. Kalau sebuah file mengimpor
keduanya, `R.string.…` jadi ambigu dan harus ditulis lengkap:

```swift
CoreUI.R.string.button.next.text
```

Untuk ribuan pemakaian, itu bukan perubahan kecil.

### Saran: jangan berbagi `R` antar module

Yang jauh lebih murah:

- **Resource fitur ikut fitur.** Setiap package fitur membawa string dan
  asset-nya sendiri, menghasilkan `R` sendiri, dan tidak ada yang ambigu karena
  tidak ada yang mengimpor dua `R` sekaligus.
- **Yang benar-benar bersama** — "Lanjut", "Batal", ikon umum — naik ke `CoreUI`
  dengan `R` yang `public`. Jumlahnya sedikit, jadi menulisnya lengkap tidak
  memberatkan.

Kalau `CoreUI`-nya kecil, pertimbangkan **tanpa R.swift sama sekali** di sana:

```swift
public enum CoreStrings {
    public static let next = String(
        localized: "button.next",
        bundle: .module
    )
}
```

Tidak ada plugin, tidak ada langkah build tambahan, dan tetap aman dari salah
ketik.

### Satu jebakan senyap yang harus diketahui

Asset di dalam package **tidak** ditemukan lewat `Image("nama")` biasa. Tanpa
bundle-nya, SwiftUI mencari di main bundle, tidak menemukan apa-apa, dan
menggambar kosong — **tanpa error, tanpa crash**.

```swift
Image("iconTransfer")                    // kosong, diam
Image("iconTransfer", bundle: .module)   // benar
```

Ini langsung mengenai `ImageViewModel` Anda, yang menyimpan nama gambar sebagai
`String`. Begitu ada asset yang tinggal di package, ia butuh `bundle` ikut
disimpan — dan sebelum itu ada, setiap gambar dari package akan hilang diam-diam.
Kalau Lapis 3 dikerjakan, kerjakan `ImageViewModel` di hari yang sama.

---

## Networking tetap di project — lalu bagaimana package memanggilnya?

Package mendeklarasikan **apa yang ia butuhkan**, project yang memenuhinya.

```swift
// di dalam PaymentFeature (package)
public protocol BillFetching {
    func fetchBills(
        for accountNumber: String,
        completion: @escaping (Result<[Bill], Error>) -> Void
    )
}
```

```swift
// di project — Alamofire, session, header, semua tetap di sini
extension BillService: BillFetching {}

// di composition root
PaymentFlowCoordinator(navigator: navigator, billFetching: BillService())
```

Alamofire tidak pernah masuk package, dan package tidak tahu Alamofire ada.
Anda juga tidak perlu memindahkan satu baris pun kode networking — cukup satu
`extension` sebaris di project untuk menyatakan bahwa service yang sudah ada
memenuhi protokolnya.

Efek sampingnya bagus: test fitur cukup memberi implementasi palsu, tanpa
jaringan dan tanpa menyentuh project.

---

## Fitur tidak boleh saling impor

Dashboard menuju ke mana-mana. Kalau Dashboard memanggil
`AppRouter.shared.start(.payment(...))`, ia harus mengimpor `PaymentFeature` —
dan akhirnya bergantung pada semua fitur.

Polanya sama dengan yang sudah kita pakai di tingkat layar: fitur menyatakan
niat sebagai closure, **project** yang memetakannya.

```swift
// di project — satu-satunya yang melihat seluruh graf
DashboardRouting(
    onSelectPayment: {
        AppRouter.shared.start(.payment(billNumber: ""))
    }
)
```

`extension PendingFlow { static func payment(…) }` tinggal di package fitur.
Yang memanggilnya hanya project.

Ini alasan `TransferLandingFactory.Routing` dibuat. Masalah yang sama, skala
berbeda.

---

## Backward: dari tengah flow UIKit ke SwiftUI, lalu kembali

Dua kasus, dan jawabannya berbeda. Yang sering tertukar justru ini.

### Kasus A — layar SwiftUI-nya masuk ke tumpukan flow

```swift
navigator.push(Screen { LayarLama(viewModel: vm) })
navigator.pushIsland(CoordinatorLama(...))          // rangkaian, bukan satu layar
```

Layarnya berada di tumpukan yang sama, jadi **kembalinya pop biasa** — tombol
back maupun swipe. Flow tidak pernah ditinggalkan, state-nya utuh, dan
`goBack(to:)` bisa melompati layar itu.

**Ini yang Anda mau di hampir semua kasus.**

### Kasus B — benar-benar keluar ke dunia `NavigationView` lama

Kalau tujuannya adalah layar yang tinggal di tumpukan `NavigationView` milik
Dashboard, maka flow-nya **ditutup**, bukan ditumpuk. Setelah itu tidak ada
"kembali ke flow" — tumpukannya sudah dilepas beserta seluruh ViewModel-nya.

Kalau pengguna harus kembali, jalannya membuka flow lagi **pada langkah
tertentu**, bukan dari awal:

```swift
// menutup flow sambil menyerahkan hasilnya ke dunia SwiftUI
navigator.finish()

// nanti, masuk lagi di tengah
AppRouter.shared.start(.transfer(transferCart: cart))   // + parameter langkahnya
```

`FlowNavigator.setStack` dan `createController(for:stepIdentifier:)` ada persis
untuk itu: coordinator menyusun `[landing, langkahTujuan]` supaya tombol
back-nya tetap masuk akal.

### Aturannya satu kalimat

**Selama masih di dalam perjalanan yang sama, pakai `push`/`pushIsland` — jangan
menutup flow.** Menutup flow adalah "perjalanan ini selesai", bukan "pindah
layar".

---

## Dua biaya yang tetap ada

**`public` di mana-mana**, termasuk inisialiser — dan inisialiser `public` tidak
dibuatkan otomatis untuk struct. Untuk `FlowKit` ini pekerjaan setengah jam;
untuk package fitur nanti, jauh lebih panjang.

**`R.swift` menjadi per-module.** Ini yang paling menentukan di tahap 2, dan
sebaiknya diputuskan sebelum package fitur pertama dibuat: resource fitur ikut
pindah, atau naik ke package UI bersama. Di tahap 1 tidak muncul sama sekali,
karena `FlowKit` tidak menyentuh resource.

---

## Kaitannya dengan revamp

Dua keputusan yang sudah diambil mempermudah pemecahan ini, dan itu bukan
kebetulan:

- **Coordinator sebagai objek, bukan `View`.** Coordinator berbentuk view harus
  duduk di dalam pohon view, jadi batas package akan memotong di tempat yang
  salah. Sebagai objek, ia bisa tinggal di mana pun — project sekarang, package
  nanti — tanpa mengubah apa pun di sekitarnya.
- **Router global yang tidak tahu daftar tujuan.** `AppRouter` tidak menyebut
  satu pun fitur, jadi `FlowKit` tidak pernah bergantung ke atas. Kalau daftar
  tujuannya global, package akan bergantung pada semua fitur dan graf-nya
  melingkar.

Urutan yang disarankan tetap sama: buktikan navigasinya di satu flow lebih
dulu, baru pindahkan `FlowKit` ke package. Memindahkan lebih dulu hanya
menambah satu variabel saat ada yang tidak beres.
