# Peta folder → package

Pemetaan dari struktur folder yang ada sekarang ke package. Disusun dari nama
foldernya, jadi **beberapa perlu Anda buka dulu untuk memastikan isinya** —
ditandai di kolom catatan.

---

## Yang menentukan kesulitannya

Struktur Anda **per tipe**, bukan per fitur: semua `UIComponents` di satu tempat,
semua `Models` di satu tempat, semua `UIScreens` di satu tempat.

Untuk lapis bersama itu justru menguntungkan — `Constants`, `Extensions`,
`TypeAliases` sudah terkumpul, tinggal dipindah. Tetapi untuk fitur itu
menyulitkan: satu fitur tersebar di `UIScreens`, `Models`, `Services`, dan
`Transformer` sekaligus. **Memotong fitur adalah pekerjaan yang sebenarnya**,
dan itu sebabnya fitur dikerjakan terakhir.

---

## Di mana package-nya ditaruh

**Selevel dengan `Byon/`, di root repo — bukan di dalamnya.**

```
repo/
  Byon.xcodeproj
  Byon/                     ← target aplikasi, menyusut seiring waktu
  ByonTests/
  Packages/
    Platform/               ← satu Package.swift, banyak target
      Sources/
        Core/
        DesignSystem/
        Domain/
        Components/
        Navigation/
        Routes/
      Tests/
    TransferFeature/        ← satu package per fitur, satu pemilik
    PaymentFeature/
  Frameworks/
```

Empat alasan, dan yang pertama paling menentukan:

1. **Arah dependensinya App → Package.** Menaruh package di dalam `Byon/`
   menyiratkan kebalikannya, dan orang baru akan membacanya begitu.
2. **`Byon/` adalah sumber target aplikasi.** File di dalamnya mudah ikut
   ter-*target membership* tanpa sengaja — dan file package yang juga
   dikompilasi App target adalah bug yang membingungkan.
3. **CODEOWNERS, CI, dan cache** lebih bersih dengan `Packages/*` sebagai jalur
   tersendiri.
4. **`swift build` dan `swift test`** bisa dijalankan langsung dari folder
   package-nya, tanpa Xcode sama sekali. Itu yang membuat CI per squad murah.

### Satu package untuk lapis bersama, satu per fitur

`Platform` menampung enam target sekaligus, bukan enam package. Alasannya
praktis: keenamnya berubah bersamaan dan dimiliki orang yang sama, sementara
enam `Package.swift` berarti enam kali pekerjaan tiap kali ada perubahan
dependensi.

Yang perlu diketahui supaya pilihan ini tidak terasa seperti kompromi:
**batas antar target ditegakkan kompiler sama kuatnya dengan batas antar
package.** `DesignSystem` tetap tidak bisa menyebut `Components` kalau tidak
dideklarasikan di `Package.swift`. Yang hilang hanya versioning terpisah, dan
untuk package lokal itu memang tidak dipakai.

Fitur tetap satu package masing-masing — di situ pemisahannya bukan soal
kompilasi, tapi soal kepemilikan dan konflik antar squad.

### Yang tetap tinggal di `Byon/`

`Services`, `Managers`, `Resources`, `Assets`, `Configs`, `Entitlements`,
`R.generated`, `AppDelegate`/`SceneDelegate`, dan pemasangan `setFlowResolver`.
Folder itu tidak akan hilang — ia menyusut sampai berisi komposisi dan hal-hal
yang memang milik aplikasi.

---

## Package yang diusulkan

| Package | Isinya | Bergantung pada | Dibuat saat |
|---|---|---|---|
| **Navigation** | `Sources/Navigation` + `DebugTool` | — | langkah 1, bisa paling awal |
| **Core** | `TypeAliases`, extension tanpa UI, konstanta murni, enum teknis | — | langkah 2 |
| **DesignSystem** | token visual (`Spaces`, `IconSizes`, warna, font), `UIViewModifier`, extension yang butuh UI | Core | langkah 3 |
| **Domain** | `UseCase` base, model bersama, `Transformer` bersama, konstanta bisnis (`Currencies`) | Core | langkah 4 |
| **Routes** | `enum AppRoute` saja, tidak ada yang lain | Navigation, Domain | saat perpindahan lintas fitur pertama muncul |
| **Components** | `UIComponents`, `UIWidgets`, `UIForms`, `UINavigationBar`, `UIChart`, `UIViewRepresentable`, lalu `Screen` paling akhir | DesignSystem, Core | langkah 5 |
| **`<Nama>`Feature** | layar + ViewModel + UseCase + model milik fitur, coordinator flow, `extension PendingFlow` | semua di atas | langkah 6, satu per squad |

**Tetap di App target:** `Services`, `Managers`, `Resources`, `Assets`,
`Configs`, `Entitlements`, `Vendors`, `Frameworks`, `R.generated`,
`AppDelegate`/`SceneDelegate`, dan pemasangan `setFlowResolver`.

### Satu nama yang tidak boleh dipakai

Prefiks aplikasi sengaja tidak dipakai supaya `import`-nya enak dibaca —
`import Core`, `import DesignSystem`, `import Navigation`. Tetapi satu nama
harus dihindari: **`Foundation`**. Itu framework Apple, dan package dengan nama
itu menabraknya di setiap file yang mengimpor keduanya.

Karena itu lapis paling bawah bernama `Core`, bukan `Foundation`.

Nama lain yang lebih baik dijauhi karena alasan yang sama: `Combine`,
`Dispatch`, `Network`, `Contacts`, `Intents`, `Charts` — semuanya framework
Apple. `Charts` khususnya relevan kalau `UIChart` nanti jadi package sendiri;
namai `Charting` atau `ChartComponents`.

### Arah dependensinya

```
Core ─┬─► DesignSystem ──► Components ─┐
                └─► Domain ───────────────────────┬─┤
                                                      │ │
Navigation ──────────────────────────────────┬────┘ │
                                                 │      │
                              Routes ◄────┘      │
                                    ▲                   │
                                    └───────────── <Nama>Feature
                                                        │
                                             App target ◄┘
```

Tidak ada panah yang kembali ke atas, dan **tidak ada panah antar fitur.** Itu
yang harus tetap benar; sisanya bisa disesuaikan.

---

## Satu package per fitur, dan `Navigation` tidak ikut tumbuh

Kekhawatiran "ujungnya jadi massive" wajar, tapi namanya yang salah — salah
saya. **`Navigation` adalah infrastrukturnya, bukan kumpulan flow.** Isinya
enam file: `AppRouter`, `FlowPresenter`, `FlowNavigationController`,
`FlowNavigator`, `FlowStepHostingController`, `LazyNavigationLink`. Jumlah itu
tidak berubah saat fitur kesepuluh ditambahkan — memang itu tujuan `PendingFlow`
dibuat sebagai closure, bukan enum berisi seluruh tujuan aplikasi.

Flow-nya sendiri tinggal di package fiturnya masing-masing.

### Per fitur, bukan per flow

Alasan Anda soal konflik antar squad tepat, dan package memberi lebih dari itu:
build dan test yang berdiri sendiri, isolasi yang ditegakkan kompiler, dan
kepemilikan yang jelas lewat CODEOWNERS per folder.

Tapi granularitasnya **per fitur**, bukan per flow. Satu fitur sering punya
beberapa flow — transfer punya flow transaksi, dan mungkin nanti flow kelola
penerima — yang berbagi model, service, dan komponen yang sama. Memecahnya per
flow menghasilkan belasan package kecil yang saling menyebut, dan itu lebih
buruk daripada satu package yang jelas pemiliknya.

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
