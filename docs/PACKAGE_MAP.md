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

Enam, bukan dua puluh. Batas package yang terlalu banyak menghabiskan lebih
banyak waktu daripada yang dihemat.

```
ByonFoundation      tanpa UI sama sekali
    ↑
ByonDesignSystem    token, modifier, style
    ↑
ByonUIKitchen       komponen yang bisa dipakai ulang
    
ByonDomain          UseCase base, model, transformer      (→ ByonFoundation)
ByonFlow            navigasi + lifecycle                  (berdiri sendiri)

<Nama>Feature       satu per fitur, dipotong dari UIScreens
```

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
| `DebugTool` | **ByonFlow** | gabung dengan `Sources/Debug` |
| `UIScreens` | **dipotong per fitur** | pekerjaan terbesar, dikerjakan terakhir |
| `Services` | **tetap di app** | networking tetap di project, sesuai keputusan Anda |
| `Managers` | **tetap di app** | fitur menyebutnya lewat protokol yang fitur itu deklarasikan |
| `Resources` | **tetap di app**, sementara | `R` menjadi per-module begitu pindah — lihat MODULARIZATION.md |
| `Assets` | **tetap di app**, sementara | sama, plus jebakan `Bundle.module` |
| `Configs` | **tetap di app** | konfigurasi build |
| `Entitlements` | **tetap di app** | |
| `Vendors`, `Frameworks` | **tetap di app** | pihak ketiga |

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
4. **`ByonFlow`** — `Sources/Navigation` + `DebugTool`. Bisa kapan saja,
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
