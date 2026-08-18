# Peta package dan foldering

Dua hal yang sering tertukar, jadi dipisahkan tegas di sini:

- **Package** = satu `Package.swift`. Jumlahnya sedikit.
- **Target** = satu modul yang di-`import`. Satu package boleh punya banyak.

Batas antar **target** ditegakkan kompiler sama kuatnya dengan batas antar
package. Jadi banyak target dalam satu package tidak melonggarkan apa pun —
yang berkurang hanya jumlah `Package.swift` yang harus diurus.

---

## Daftar local SPM package

| # | Package | Isinya | Pemilik |
|---|---|---|---|
| 1 | **Platform** | enam target lapis bersama — lihat tabel di bawah | tim core |
| 2 | **TransferFeature** | satu fitur utuh | satu squad |
| 3 | **PaymentFeature** | satu fitur utuh | satu squad |
| … | **`<Nama>`Feature** | seterusnya, satu per fitur | satu squad |

**Dua package untuk memulai**: `Platform` dan satu fitur pertama. Sisanya
menyusul saat fiturnya dikerjakan.

### Enam target di dalam `Platform`

| Target | Isinya | Bergantung pada |
|---|---|---|
| **Core** | `TypeAliases`, extension tanpa UI, konstanta murni, enum teknis | — |
| **Navigation** | `Sources/Navigation` + `DebugTool` | — |
| **DesignSystem** | token visual (`Spaces`, `IconSizes`, warna, font), `UIViewModifier`, extension yang butuh UI | Core |
| **Domain** | `UseCase` base, model bersama, `Transformer` bersama, konstanta bisnis (`Currencies`) | Core |
| **Components** | `UIComponents`, `UIWidgets`, `UIForms`, `UINavigationBar`, `UIChart`, `UIViewRepresentable`, lalu `Screen` paling akhir | Core, DesignSystem |
| **Routes** | `enum AppRoute` saja | Navigation, Domain |

Import-nya nanti: `import Core`, `import Navigation`, `import DesignSystem`.

---

## Foldering

`Packages/` selevel dengan `Byon/`, di root repo — **bukan di dalamnya.**

```
repo/
  Byon.xcodeproj
  Byon/                          target aplikasi, menyusut seiring waktu
    Services/  Managers/
    Resources/ Assets/
    Configs/   Entitlements/
    AppDelegate.swift            + pemasangan setFlowResolver
  ByonTests/
  Frameworks/

  Packages/
    Platform/
      Package.swift
      Sources/
        Core/
        Navigation/
        DesignSystem/
        Domain/
        Components/
        Routes/
      Tests/
        NavigationTests/

    TransferFeature/
      Package.swift
      Sources/
        TransferFeature/
          Flow/                  TransferFlowCoordinator.swift
          Landing/               Screen, ViewModel, UseCase, Factory
          Models/                model milik transfer saja
      Tests/
        TransferFeatureTests/
```

### Kenapa `Packages/` di luar `Byon/`

1. **Arah dependensinya App → Package.** Menaruhnya di dalam `Byon/`
   menyiratkan kebalikannya, dan orang baru akan membacanya begitu.
2. **`Byon/` adalah sumber target aplikasi.** File di dalamnya gampang ikut
   target membership tanpa sengaja — dan file package yang juga dikompilasi App
   target adalah bug yang membingungkan.
3. **CODEOWNERS, CI, dan cache** lebih bersih dengan `Packages/*` sebagai jalur
   tersendiri. Untuk pembagian per squad ini langsung terasa.
4. **`swift build` dan `swift test`** jalan dari folder package-nya tanpa Xcode.
   Itu yang membuat CI per squad murah.

---

## `Package.swift`

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Platform",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Components", targets: ["Components"]),
        .library(name: "Routes", targets: ["Routes"])
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Navigation"),
        .target(name: "DesignSystem", dependencies: ["Core"]),
        .target(name: "Domain", dependencies: ["Core"]),
        .target(name: "Components", dependencies: ["Core", "DesignSystem"]),
        .target(name: "Routes", dependencies: ["Navigation", "Domain"]),
        .testTarget(name: "NavigationTests", dependencies: ["Navigation"])
    ]
)
```

Baris `dependencies:` itu yang menegakkan susunannya. Kalau ada yang menulis
`import Components` di dalam `DesignSystem`, build gagal — bukan review yang
harus menangkapnya.

Package fitur menyebut `Platform` lewat path relatif:

```swift
dependencies: [.package(path: "../Platform")]
```

### Cara memulainya

Buat `Package.swift` dengan **target `Navigation` saja** dulu. Buktikan aplikasi
build dan flow transfer masih jalan. Baru tambahkan target berikutnya satu per
satu.

Kalau ada yang tidak beres — biasanya `public` yang terlewat atau resource yang
tidak ikut — cakupannya kecil dan jelas letaknya.

---

## Satu nama yang tidak boleh dipakai

Prefiks aplikasi sengaja tidak dipakai supaya `import`-nya enak dibaca. Tetapi
satu nama harus dihindari: **`Foundation`**. Itu framework Apple, dan target
dengan nama itu menabraknya di setiap file yang mengimpor keduanya — yaitu
hampir semua file. Karena itu lapis paling bawah bernama `Core`.

Nama lain yang lebih baik dijauhi karena alasan sama: `Combine`, `Dispatch`,
`Network`, `Contacts`, `Intents`, `Charts`. Yang terakhir relevan kalau
`UIChart` nanti dipisah — namai `Charting`, jangan `Charts`.

---

## Arah dependensinya

```
Core ─┬─► DesignSystem ──► Components ─┐
      └─► Domain ────────────────────┬─┤
                                     │ │
Navigation ─────────────────────┬────┘ │
                                │      │
                  Routes ◄──────┘      │
                     ▲                 │
                     └──────── <Nama>Feature
                                       │
                            App target ◄┘
```

Dua sifat yang harus tetap benar: **tidak ada panah yang kembali ke atas**, dan
**tidak ada panah antar fitur.**

---

## Yang menentukan kesulitannya

Struktur folder Anda **per tipe**, bukan per fitur: semua `UIComponents` di satu
tempat, semua `Models` di satu tempat, semua `UIScreens` di satu tempat.

Untuk lapis bersama itu menguntungkan — `Constants`, `Extensions`,
`TypeAliases` sudah terkumpul, tinggal dipindah. Tetapi untuk fitur itu
menyulitkan: satu fitur tersebar di `UIScreens`, `Models`, `Services`, dan
`Transformer` sekaligus. **Memotong fitur adalah pekerjaan yang sebenarnya**,
dan itu sebabnya fitur dikerjakan terakhir.

---

## Kenapa `Navigation` tidak ikut tumbuh

Kekhawatiran "ujungnya jadi massive" wajar, tapi penamaannya yang salah — salah
saya. **`Navigation` adalah infrastrukturnya, bukan kumpulan flow.** Isinya enam
file: `AppRouter`, `FlowPresenter`, `FlowNavigationController`, `FlowNavigator`,
`FlowStepHostingController`, `LazyNavigationLink`. Jumlah itu tidak berubah saat
fitur kesepuluh ditambahkan — memang itu tujuan `PendingFlow` dibuat sebagai
closure, bukan enum berisi seluruh tujuan aplikasi.

Flow-nya sendiri tinggal di package fiturnya masing-masing.

### Per fitur, bukan per flow

Package memberi build dan test yang berdiri sendiri, isolasi yang ditegakkan
kompiler, dan kepemilikan yang jelas lewat CODEOWNERS.

Tapi granularitasnya **per fitur**. Satu fitur sering punya beberapa flow —
transfer punya flow transaksi, mungkin nanti flow kelola penerima — yang berbagi
model, service, dan komponen yang sama. Memecahnya per flow menghasilkan
belasan package kecil yang saling menyebut, dan itu lebih buruk daripada satu
package yang jelas pemiliknya.

Ukurannya: **satu package untuk satu domain yang dimiliki satu squad.**

---

## Tabel pemetaan

| Folder sekarang | Ke mana | Catatan |
|---|---|---|
| `TypeAliases` | **Core** | daun, pindah pertama |
| `Enums` | **Core** / **Domain** | pisahkan: enum teknis vs enum bisnis |
| `Constants` | **dipecah** | token visual → DesignSystem; konstanta bisnis → Domain; sisanya Foundation |
| `Extensions` | **dipecah** | yang menyebut SwiftUI/UIKit → DesignSystem; sisanya Foundation |
| `Utilities` | **buka dulu** | biasanya campuran; pecah mengikuti isinya, jangan pindah utuh |
| `Commons` | **buka dulu** | nama yang tidak menolak apa pun — hampir pasti isinya tiga lapis berbeda |
| `Systems` | **buka dulu** | tidak bisa ditebak dari namanya |
| `UIViewModifier` | **DesignSystem** | termasuk `.invisible()` dan `.setHidden()` |
| `UIComponents` | **Components** | |
| `UIWidgets` | **Components** | |
| `UIForms` | **Components** | |
| `UINavigationBar` | **Components** | |
| `UIChart` | **Components** | kandidat package sendiri kalau berat |
| `UIViewRepresentable` | **Components** | kecuali yang membungkus SDK pihak ketiga — itu tetap di app |
| `UIContainer` | **Components**, terakhir | kemungkinan berisi `Screen` — lihat catatan di bawah |
| `UseCase` | **Domain** | base-nya saja; UseCase milik fitur ikut fiturnya |
| `Models` | **Domain** + fitur | model bersama naik, model fitur ikut fiturnya |
| `Transformer` | **Domain** + fitur | aturan sama dengan Models |
| `DebugTool` | **Navigation** | gabung dengan `Sources/Debug` |
| `UIScreens` | **dipotong per fitur** | pekerjaan terbesar, dikerjakan terakhir |
| `Services` | **tetap di app** | networking tetap di project, sesuai keputusan Anda |
| `Managers` | **tetap di app** | fitur menyebutnya lewat protokol yang fitur itu deklarasikan |
| `Resources` | **tetap di app**, sementara | `R` menjadi per-module begitu pindah — lihat MODULARIZATION.md |
| `Assets` | **tetap di app**, sementara | sama, plus jebakan `Bundle.module` |
| `Configs` | **tetap di app** | konfigurasi build |
| `Entitlements` | **tetap di app** | |
| `Vendors`, `Frameworks` | **tetap di app** | pihak ketiga |

---

## Perpindahan antar fitur, tanpa package saling mengimpor

Ini persoalan yang paling menentukan apakah pemecahan per fitur bertahan.

Layar di `PaymentFeature` perlu membuka flow transfer. Kalau ia memanggil
`PendingFlow.transfer(...)` langsung, `PaymentFeature` harus mengimpor
`TransferFeature` — dan begitu beberapa fitur saling menuju, graf-nya jadi jaring
dan keuntungan package hilang.

Jawabannya **satu package kontrak yang sangat kecil**:

```
Routes            enum AppRoute, tidak berisi kode apa pun selain itu
    ↑                    (bergantung ke Domain untuk tipe muatannya)
semua package fitur
```

```swift
// Routes — dilihat semua fitur, tidak melihat satu pun fitur
public enum AppRoute: FlowRoute {
    case transfer(TransferCart)
    case payment(Bill)
    case cardDetail(String)
}
```

```swift
// PaymentFeature — tidak tahu TransferFeature ada
AppRouter.shared.start(AppRoute.transfer(cart))
```

```swift
// App target — satu-satunya yang melihat seluruh graf
AppRouter.shared.setFlowResolver { route in
    switch route as? AppRoute {
    case .transfer(let cart): return .transfer(transferCart: cart)
    case .payment(let bill):  return .payment(bill: bill)
    default:                  return nil
    }
}
```

Yang didapat:

- Fitur **tidak pernah** saling mengimpor. Graf-nya tetap pohon.
- `Navigation` tetap tidak tahu satu pun fitur — `FlowRoute` cuma penanda
  kosong.
- Menambah perpindahan lintas fitur = satu case di `AppRoute` + satu baris di
  resolver. Package fitur yang dituju tidak disentuh.
- Deeplink dan notifikasi memakai jalur yang sama persis.

Biayanya jujur: `AppRoute` satu file yang disunting semua squad. Tetapi ia enum
kecil yang jarang berubah — konflik di situ sepele dibanding jaring dependensi
antar package, dan konfliknya kelihatan, bukan tersembunyi di graf build.

### Kapan tetap pakai closure

Untuk **entry point** — Dashboard menentukan tombolnya menuju ke mana — closure
tetap lebih baik: Dashboard tidak perlu tahu rute apa pun, App target yang
mengisinya. Pakai kontrak rute untuk perpindahan yang bisa datang dari mana saja
(deeplink, notifikasi, dialog error yang menawarkan "top up"), dan closure untuk
komposisi yang memang tempatnya di App target.

---

## Menjawab dua pertanyaan langsung

### "Base masuk mana?"

Terpisah, karena "base" di aplikasi Anda ada dua dan nasibnya berbeda.

**`UseCase` base** → `Domain`, dan bisa **lebih awal**. Ia tidak menyebut
UI sama sekali; yang disebutnya `TypeAliases` dan model. Setelah `Core`
jadi, ini langkah berikutnya yang murah.

**`Screen`, `ScreenContentViewModel`, `PaginationScreenContentViewModel`** →
`Components`, dan **paling akhir**. Ketiganya menyebut token, resource,
analytic, snackbar, dan `AppState` sekaligus. Kalau dipindah sebelum lapis di
bawahnya siap, ia menyeret semuanya dan setiap flow lama ikut tersenggol.

Periksa dulu isi `UIContainer` — kalau `Screen` ada di sana, folder itu tidak
bisa dipindah utuh sekaligus.

### "Extension?"

**Jangan dipindah utuh.** `Extensions` hampir selalu berisi dua jenis yang
lapisannya berbeda:

```
Extensions/
  String+Formatting.swift      → Core   (tanpa UI)
  Int+Ordinal.swift            → Core   (nextNumber, ordinalText)
  Date+Display.swift           → Core
  View+Invisible.swift         → DesignSystem (butuh SwiftUI)
  Color+Semantic.swift         → DesignSystem
  UIApplication+EndEditing.swift → DesignSystem (butuh UIKit)
```

Pemisahnya satu pertanyaan: **apakah file ini butuh `import SwiftUI` atau
`import UIKit`?** Kalau tidak, ia Foundation. Kalau ya, ia DesignSystem.

Gunanya nyata: `Core` yang bersih dari UI bisa dipakai target test dan
lapisan domain tanpa menyeret SwiftUI ikut dikompilasi.

---

## Tiga folder yang harus dibuka dulu

`Commons`, `Utilities`, `Systems` — ketiganya tidak bisa dipetakan dari namanya.

Dua yang pertama adalah pola yang sudah dikenal: nama yang tidak menolak apa
pun, jadi apa pun yang tidak jelas tempatnya berakhir di sana. Kemungkinan
besar isinya menyebar ke tiga sampai empat package berbeda.

Jangan memindahkannya utuh ke satu package. Kalau dipindah utuh, folder
buangannya ikut pindah dan sekarang jadi buangan **yang dipakai bersama** —
lebih sulit dibersihkan daripada sebelumnya.

---

## Urutan

1. **`Core`** — `TypeAliases`, extension non-UI, konstanta murni.
   Daun semua, nol risiko.
2. **`DesignSystem`** — token dari `Constants`, `UIViewModifier`, extension
   yang butuh UI.
3. **`Domain`** — `UseCase` base, model bersama, `Transformer` bersama.
4. **`Navigation`** — `Sources/Navigation` + `DebugTool`. Bisa kapan saja,
   bahkan paling awal, karena tidak bergantung pada satu pun di atas.
5. **Berhenti dan nilai ulang.** Empat package itu sudah membuat sisanya jauh
   lebih mudah, dan tidak satu pun menyentuh layar.
6. **`Components`** — komponen, lalu `Screen` paling akhir.
7. **Fitur pertama**, dipotong dari `UIScreens`. Mulai dari yang paling sedikit
   bergantung pada yang lain, bukan yang paling penting.

Langkah 1–4 bisa dikerjakan sebagai **pemindahan folder di dalam satu target
dulu**, tanpa `Package.swift` sama sekali. Kalau susunannya sudah rapi dan
tidak ada yang melingkar, barulah dijadikan package. Memisahkan dua pekerjaan
itu membuat kesalahan jauh lebih mudah dilacak: yang satu soal susunan, yang
satu soal `public` dan build setting.
