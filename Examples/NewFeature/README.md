# Template flow baru

Salin folder ini, ganti seluruh kata `NewFeature` dengan nama fitur Anda.

## Yang wajib

**Satu file:** `NewFeatureFlowCoordinator.swift`.

Isinya dua hal — class coordinator-nya, dan pendaftarannya ke `PendingFlow` di
bagian bawah. Tidak ada yang lain.

Setelah itu, dari mana pun di aplikasi:

```swift
AppRouter.shared.start(.newFeature(entryParameter: value))
```

`Sources/Navigation/` tidak disentuh sama sekali — sekarang maupun saat flow
kesepuluh ditambahkan.

## Yang tidak wajib, dan kapan mulai perlu

| Tambahan | Baru perlu kalau |
|---|---|
| `enum Route` + `Step` | perlu **masuk ke tengah** flow dari luar, atau `goBack(to:)` ke langkah bernama |
| `struct ScreenFactories` | coordinator harus **berhenti tahu** cara membangun layar tujuan — layarnya milik tim lain, atau ingin meng-unit-test coordinator tanpa layarnya |
| `SomeScreenFactory` per layar | layar itu punya **dua** pemanggil, misalnya flow baru dan coordinator `NavigationView` lama yang masih dipakai |
| file `+Sesuatu` | file induknya melewati batas 250 baris |

Kalau tidak ada satu pun yang berlaku, jangan dibuat. Menambahkannya nanti
murah; mencabut struktur yang terlanjur dipakai di banyak tempat tidak.

## Yang perlu diperhatikan saat mengisi

**`retainForFlowLifetime` hanya dipanggil coordinator teratas.** Kalau flow-nya
besar dan Anda memecahnya menjadi beberapa coordinator yang berbagi navigator
yang sama, coordinator anak dipegang **induknya** — bukan dititipkan lagi ke
navigator. Kalau anak ikut memanggilnya, ia menimpa titipan induknya dan induk
lepas diam-diam.

**Arti tombol back berbeda per posisi.** Di layar pertama tumpukan, back berarti
`navigator.finish()`. Di layar mana pun setelahnya, `navigator.pop()`. Kalau
sebuah layar bisa berada di dua posisi, pakai `navigator.isAtRoot` untuk
memilih.

**Closure yang disimpan di UseCase selalu `[weak self]`.** ViewModel menyimpan
UseCase, jadi closure yang menangkap ViewModel atau coordinator menutup
lingkaran.

**Jangan mempresentasikan flow dari dalam flow.** Di dalam flow, semuanya
`navigator.push`. `AppRouter` hanya memegang satu flow dan akan menolak dengan
`assertionFailure`.

## Contoh yang sudah jadi

`../TransferFeature/` adalah flow yang sudah tumbuh besar — sembilan tujuan,
butuh masuk ke tengah, dan layar tujuannya belum semua dipindah. Karena itu ia
punya enum rute dan struct factory. **Jangan menyalin bentuk itu untuk flow
baru**; salin folder ini.
