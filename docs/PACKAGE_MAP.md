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

## Package yang diusulkan

| Package | Isinya | Bergantung pada | Dibuat saat |
|---|---|---|---|
| **ByonNavigation** | `Sources/Navigation` + `DebugTool` | — | langkah 1, bisa paling awal |
| **ByonFoundation** | `TypeAliases`, extension tanpa UI, konstanta murni, enum teknis | — | langkah 2 |
| **ByonDesignSystem** | token visual (`Spaces`, `IconSizes`, warna, font), `UIViewModifier`, extension yang butuh UI | ByonFoundation | langkah 3 |
| **ByonDomain** | `UseCase` base, model bersama, `Transformer` bersama, konstanta bisnis (`Currencies`) | ByonFoundation | langkah 4 |
| **ByonAppRoutes** | `enum AppRoute` saja, tidak ada yang lain | ByonNavigation, ByonDomain | saat perpindahan lintas fitur pertama muncul |
| **ByonUIKitchen** | `UIComponents`, `UIWidgets`, `UIForms`, `UINavigationBar`, `UIChart`, `UIViewRepresentable`, lalu `Screen` paling akhir | ByonDesignSystem, ByonFoundation | langkah 5 |
| **`<Nama>`Feature** | layar + ViewModel + UseCase + model milik fitur, coordinator flow, `extension PendingFlow` | semua di atas | langkah 6, satu per squad |

**Tetap di App target:** `Services`, `Managers`, `Resources`, `Assets`,
`Configs`, `Entitlements`, `Vendors`, `Frameworks`, `R.generated`,
`AppDelegate`/`SceneDelegate`, dan pemasangan `setFlowResolver`.

### Arah dependensinya

```
ByonFoundation ─┬─► ByonDesignSystem ──► ByonUIKitchen ─┐
                └─► ByonDomain ───────────────────────┬─┤
                                                      │ │
ByonNavigation ──────────────────────────────────┬────┘ │
                                                 │      │
                              ByonAppRoutes ◄────┘      │
                                    ▲                   │
                                    └───────────── <Nama>Feature
                                                        │
                                             App target ◄┘
```

Tidak ada panah yang kembali ke atas, dan **tidak ada panah antar fitur.** Itu
yang harus tetap benar; sisanya bisa disesuaikan.

---

## Satu package per fitur, dan `ByonNavigation` tidak ikut tumbuh

Kekhawatiran "ujungnya jadi massive" wajar, tapi namanya yang salah — salah
saya. **`ByonNavigation` adalah infrastrukturnya, bukan kumpulan flow.** Isinya
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
| `TypeAliases` | **ByonFoundation** | daun, pindah pertama |
| `Enums` | **ByonFoundation** / **ByonDomain** | pisahkan: enum teknis vs enum bisnis |
| `Constants` | **dipecah** | token visual → DesignSystem; konstanta bisnis → Domain; sisanya Foundation |
| `Extensions` | **dipecah** | yang menyebut SwiftUI/UIKit → DesignSystem; sisanya Foundation |
| `Utilities` | **buka dulu** | biasanya campuran; pecah mengikuti isinya, jangan pindah utuh |
| `Commons` | **buka dulu** | nama yang tidak menolak apa pun — hampir pasti isinya tiga lapis berbeda |
| `Systems` | **buka dulu** | tidak bisa ditebak dari namanya |
| `UIViewModifier` | **ByonDesignSystem** | termasuk `.invisible()` dan `.setHidden()` |
| `UIComponents` | **ByonUIKitchen** | |
| `UIWidgets` | **ByonUIKitchen** | |
| `UIForms` | **ByonUIKitchen** | |
| `UINavigationBar` | **ByonUIKitchen** | |
| `UIChart` | **ByonUIKitchen** | kandidat package sendiri kalau berat |
| `UIViewRepresentable` | **ByonUIKitchen** | kecuali yang membungkus SDK pihak ketiga — itu tetap di app |
| `UIContainer` | **ByonUIKitchen**, terakhir | kemungkinan berisi `Screen` — lihat catatan di bawah |
| `UseCase` | **ByonDomain** | base-nya saja; UseCase milik fitur ikut fiturnya |
| `Models` | **ByonDomain** + fitur | model bersama naik, model fitur ikut fiturnya |
| `Transformer` | **ByonDomain** + fitur | aturan sama dengan Models |
| `DebugTool` | **ByonNavigation** | gabung dengan `Sources/Debug` |
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
ByonAppRoutes            enum AppRoute, tidak berisi kode apa pun selain itu
    ↑                    (bergantung ke ByonDomain untuk tipe muatannya)
semua package fitur
```

```swift
// ByonAppRoutes — dilihat semua fitur, tidak melihat satu pun fitur
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
- `ByonNavigation` tetap tidak tahu satu pun fitur — `FlowRoute` cuma penanda
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

**`UseCase` base** → `ByonDomain`, dan bisa **lebih awal**. Ia tidak menyebut
UI sama sekali; yang disebutnya `TypeAliases` dan model. Setelah `ByonFoundation`
jadi, ini langkah berikutnya yang murah.

**`Screen`, `ScreenContentViewModel`, `PaginationScreenContentViewModel`** →
`ByonUIKitchen`, dan **paling akhir**. Ketiganya menyebut token, resource,
analytic, snackbar, dan `AppState` sekaligus. Kalau dipindah sebelum lapis di
bawahnya siap, ia menyeret semuanya dan setiap flow lama ikut tersenggol.

Periksa dulu isi `UIContainer` — kalau `Screen` ada di sana, folder itu tidak
bisa dipindah utuh sekaligus.

### "Extension?"

**Jangan dipindah utuh.** `Extensions` hampir selalu berisi dua jenis yang
lapisannya berbeda:

```
Extensions/
  String+Formatting.swift      → ByonFoundation   (tanpa UI)
  Int+Ordinal.swift            → ByonFoundation   (nextNumber, ordinalText)
  Date+Display.swift           → ByonFoundation
  View+Invisible.swift         → ByonDesignSystem (butuh SwiftUI)
  Color+Semantic.swift         → ByonDesignSystem
  UIApplication+EndEditing.swift → ByonDesignSystem (butuh UIKit)
```

Pemisahnya satu pertanyaan: **apakah file ini butuh `import SwiftUI` atau
`import UIKit`?** Kalau tidak, ia Foundation. Kalau ya, ia DesignSystem.

Gunanya nyata: `ByonFoundation` yang bersih dari UI bisa dipakai target test dan
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

1. **`ByonFoundation`** — `TypeAliases`, extension non-UI, konstanta murni.
   Daun semua, nol risiko.
2. **`ByonDesignSystem`** — token dari `Constants`, `UIViewModifier`, extension
   yang butuh UI.
3. **`ByonDomain`** — `UseCase` base, model bersama, `Transformer` bersama.
4. **`ByonNavigation`** — `Sources/Navigation` + `DebugTool`. Bisa kapan saja,
   bahkan paling awal, karena tidak bergantung pada satu pun di atas.
5. **Berhenti dan nilai ulang.** Empat package itu sudah membuat sisanya jauh
   lebih mudah, dan tidak satu pun menyentuh layar.
6. **`ByonUIKitchen`** — komponen, lalu `Screen` paling akhir.
7. **Fitur pertama**, dipotong dari `UIScreens`. Mulai dari yang paling sedikit
   bergantung pada yang lain, bukan yang paling penting.

Langkah 1–4 bisa dikerjakan sebagai **pemindahan folder di dalam satu target
dulu**, tanpa `Package.swift` sama sekali. Kalau susunannya sudah rapi dan
tidak ada yang melingkar, barulah dijadikan package. Memisahkan dua pekerjaan
itu membuat kesalahan jauh lebih mudah dilacak: yang satu soal susunan, yang
satu soal `public` dan build setting.
