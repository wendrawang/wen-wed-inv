# Memecah ke local SPM

Rencana untuk kondisi Anda: **networking tetap di project yang ada**, yang
dipindah ke package hanya navigasi dan flow fitur baru — supaya flow lama tidak
tersenggol sama sekali, sekaligus persiapan revamp.

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
