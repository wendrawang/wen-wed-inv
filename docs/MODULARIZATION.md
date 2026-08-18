# Memecah ke local SPM

Bisa, dan naluri Anda soal Alamofire benar. Dokumen ini bentuk yang disarankan,
urutan mengerjakannya, dan dua biaya yang sering diremehkan.

---

## Isi `Sources/` sudah hampir siap

Bukan klaim, ini bisa diperiksa: seluruh `Sources/` hanya mengimpor `SwiftUI`,
`UIKit`, `Foundation`, dan `os.log`. Satu-satunya pemakaian tipe milik aplikasi
adalah `.invisible()` di `LazyNavigationLink` — sudah ditandai di kodenya.

Karena itu `Sources/Navigation` dan `Sources/Debug` adalah **package pertama
yang paling murah**, dan itu yang sebaiknya dikerjakan lebih dulu: setup SPM-nya
terbukti tanpa menyentuh apa pun yang berisiko.

---

## Bentuk yang disarankan

```
Packages/
  Core/                        satu package, beberapa target
    CoreNavigation             FlowNavigator, AppRouter, FlowPresenter, …
    CoreDebug                  LifecycleProbe, LifecycleTracker, RenderCounter
    CoreDomain                 UseCase base, TypeAliases, model bersama
    CoreNetworking             ← protokol saja, nol dependensi
    CoreNetworkingAlamofire    ← implementasinya, hanya di sini Alamofire ada
    CoreUI                     Screen, ScreenContentViewModel, komponen, R.*

  TransferFeature/             satu package per fitur
  PaymentFeature/
  DashboardFeature/

App target                     satu-satunya yang tahu seluruh graf
```

**Core satu package dengan beberapa target**, bukan enam package terpisah.
Isinya berubah bersamaan, dan satu `Package.swift` jauh lebih cepat diurus.

**Satu package per fitur**, bukan satu package `Features` berisi semua. Batasnya
justru itu yang Anda inginkan: fitur tidak boleh saling impor, dan package
terpisah membuat kompilernya yang menegakkan, bukan kesepakatan.

---

## Networking: naluri Anda benar, tapi satu langkah lagi

Menaruh pemanggilan API di Core memang tepat. Tetapi kalau protokol dan
implementasi Alamofire ada di **target yang sama**, setiap fitur yang memakai
networking ikut me-link Alamofire, dan siapa pun tetap bisa menulis
`import Alamofire` di dalam fitur.

Pisahkan satu langkah lagi:

```swift
// CoreNetworking — nol dependensi, tidak tahu Alamofire ada
public protocol HTTPClient {
    func send<Response: Decodable>(
        _ request: HTTPRequest,
        completion: @escaping (Result<Response, HTTPError>) -> Void
    )
}

// CoreNetworkingAlamofire — satu-satunya target yang menyebut Alamofire
import Alamofire

public final class AlamofireHTTPClient: HTTPClient { … }
```

| Target | Bergantung pada | Dipakai oleh |
|---|---|---|
| `CoreNetworking` | tidak ada | semua fitur |
| `CoreNetworkingAlamofire` | Alamofire | **hanya App target** |

Hasilnya tiga hal sekaligus: fitur tidak pernah melihat Alamofire bahkan secara
transitif, mengganti Alamofire dengan `URLSession` nanti menyentuh satu target,
dan test fitur cukup memberi `HTTPClient` palsu tanpa menyentuh jaringan.

**Service milik fitur tetap di fitur.** `RecipientService` memakai `HTTPClient`
dan tinggal di `TransferFeature`. Yang di Core hanya yang benar-benar dipakai
lintas fitur — sesi, auth, refresh token.

---

## Satu hal yang akan Anda temui: fitur tidak boleh saling impor

Dashboard membuka transfer. Kalau Dashboard memanggil
`AppRouter.shared.start(.transfer(...))`, `DashboardFeature` harus mengimpor
`TransferFeature` — dan Dashboard menuju ke mana-mana, jadi ia akan bergantung
pada **semua** fitur.

Jawabannya pola yang sudah kita pakai di tingkat layar: **fitur menyatakan
niat sebagai closure, App target yang memetakannya.**

```swift
// DashboardFeature — tidak tahu transfer ada
public struct DashboardRouting {
    public var onSelectTransfer: () -> Void
    public var onSelectPayment: () -> Void
}

// App target — satu-satunya yang melihat seluruh graf
DashboardFactory(
    routing: DashboardRouting(
        onSelectTransfer: {
            AppRouter.shared.start(.transfer(transferCart: TransferCart()))
        },
        onSelectPayment: {
            AppRouter.shared.start(.payment(billNumber: ""))
        }
    )
)
```

`extension PendingFlow { static func transfer(…) }` tetap tinggal di
`TransferFeature`. Yang memanggilnya hanya App target.

Ini persis alasan `TransferLandingFactory.Routing` dibuat: masalahnya sama,
hanya skalanya berbeda.

---

## Dua biaya yang sering diremehkan

**`public` di mana-mana.** Semua yang dipakai lintas package harus `public`,
termasuk inisialisernya — dan inisialiser `public` tidak dibuatkan otomatis
untuk struct. Untuk ratusan layar ini pekerjaan mekanis yang panjang. Kerjakan
per package, jangan sekaligus.

**Resource dan `R.swift`.** `R.string.…`, `R.image.…` ada di hampir setiap file.
Saat sebuah fitur pindah ke package, asset dan string-nya ikut pindah, dan
`R` yang dihasilkan menjadi **per-module** — jadi setiap referensi lintas modul
harus diputuskan: ikut pindah, atau naik ke `CoreUI`. Ini biasanya bagian
terbesar dari pekerjaan, dan sebaiknya diputuskan sebelum package fitur pertama
dibuat, bukan sesudah.

Yang **tidak** menjadi masalah: SwiftUI Preview lintas package jalan normal, dan
`#if DEBUG` di `CoreDebug` tetap bekerja seperti biasa.

---

## Urutan

1. **`CoreNavigation` + `CoreDebug`.** Nol dependensi, dan `.invisible()` satu
   satunya yang perlu diputuskan. Kalau setup SPM-nya bermasalah, ketahuannya di
   sini, saat belum ada yang bergantung padanya.
2. **`CoreNetworking` + `CoreNetworkingAlamofire`.** Pindahkan protokolnya dulu,
   implementasinya menyusul. Setelah ini App target satu-satunya yang menyebut
   Alamofire.
3. **`CoreDomain` + `CoreUI`.** Di sinilah persoalan `R.swift` muncul.
   Selesaikan di sini, sekali, untuk semua fitur.
4. **`TransferFeature`.** Fitur pertama, dan sengaja yang sudah kita rapikan —
   flow-nya satu file, layarnya sudah bersih, factory-nya sudah terpisah.
5. Fitur berikutnya mengikuti.

Langkah 3 yang paling berat. Kalau waktunya belum ada, berhenti di langkah 2 —
dua langkah pertama sudah memberi manfaat nyata dan tidak menuntut langkah
ketiga.

---

## Kaitannya dengan revamp

Dua keputusan yang sudah diambil justru mempermudah pemecahan ini, dan itu bukan
kebetulan:

- **Coordinator sebagai objek, bukan `View`.** Coordinator berbentuk view harus
  duduk di dalam pohon view, jadi batas package akan memotong di tempat yang
  salah. Sebagai objek, ia bisa tinggal di package fitur tanpa menyeret apa pun.
- **Router global yang tidak tahu daftar tujuan.** `AppRouter` di `CoreNavigation`
  tidak menyebut satu pun fitur, jadi Core tidak pernah bergantung ke atas.
  Kalau daftar tujuannya global, Core akan bergantung pada semua fitur — dan
  graf-nya melingkar.

Jadi urutannya masuk akal: buktikan navigasinya di satu flow lebih dulu, lalu
pecah. Bukan sebaliknya.
