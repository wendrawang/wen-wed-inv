# Memulai flow transfer — apa yang dibutuhkan dan urutannya

Panduan pemakaian untuk memindahkan flow transfer ke navigasi UIKit. Latar
belakang keputusannya ada di [NAVIGATION_DECISION.md](NAVIGATION_DECISION.md);
dokumen ini hanya langkah-langkahnya.

---

## Mulai dari satu file

Jangan mulai dengan dua belas file. `Examples/` memperlihatkan bentuk **akhir**
setelah sebuah flow punya sembilan tujuan; untuk memulai, yang benar-benar
dibutuhkan adalah **satu file baru dan dua baris yang diganti.**

### Satu file baru

```swift
import SwiftUI
import UIKit

final class TransferFlowCoordinator {

    private let navigator: FlowNavigator
    private let transferCart: TransferCart

    init(navigator: FlowNavigator, transferCart: TransferCart) {
        self.navigator = navigator
        self.transferCart = transferCart

        // Wajib. Seluruh layar hanya menyebut coordinator lewat `[weak self]`,
        // jadi tanpa ini ia lepas begitu `createStack()` selesai.
        navigator.retainForFlowLifetime(self)
    }

    func createStack() -> [UIViewController] {
        [navigator.createController(for: createLandingScreen())]
    }

    private func createLandingScreen() -> some View {
        Screen {
            TransferLandingScreen(viewModel: createLandingViewModel())
        }
    }

    private func createLandingViewModel() -> TransferLandingViewModel {
        let useCase = TransferLandingUseCase()
        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart

        let viewModel = TransferLandingViewModel()
        viewModel.navigationBarViewModel.title = R.string
            .navigationTitle
            .transferRecipient
            .text

        // Layar pertama tumpukan: back berarti menutup flow.
        viewModel.navigationBarViewModel.onTapBackButton = { [weak self] in
            self?.navigator.finish()
        }

        useCase.callback.onSubmissionSucceed = { [weak self, weak useCase] in
            guard let useCase = useCase else { return }
            self?.showNextStep(after: useCase)
        }

        viewModel.setUseCase(useCase)
        return viewModel
    }

    private func showNextStep(after useCase: TransferLandingUseCase) {
        // Sengaja kosong untuk uji pertama. Diisi setelah alasnya terbukti.
    }
}

extension PendingFlow {
    static func transfer(transferCart: TransferCart) -> PendingFlow {
        PendingFlow { navigator in
            TransferFlowCoordinator(
                navigator: navigator,
                transferCart: transferCart
            )
            .createStack()
        }
    }
}
```

### Dua baris yang diganti

```swift
// 1. di view terluar Main, di luar NavigationView
NavigationView { DashboardCoordinator() }
    .mountFlowRouter()

// 2. di tombol transfer Dashboard
AppRouter.shared.start(.transfer(transferCart: TransferCart()))
```

Selesai. Daftar penerima sudah muncul, tab dan pencarian sudah bekerja — semua
itu logika `TransferLandingViewModel` yang tidak disentuh sama sekali. Yang
belum: perpindahan ke tujuan berikutnya, dan itu memang sengaja.

Satu baris yang perlu Anda sesuaikan: `onTapBackButton` adalah tebakan nama.
Saya belum pernah melihat isi `NavigationBarViewModel`.

---

## Kapan file-file lain itu mulai dibutuhkan

Dua belas file di `Examples/` bukan syarat masuk. Ini kapan masing-masing
mulai berguna:

| File | Wajib? | Mulai dibutuhkan saat |
|---|---|---|
| `TransferFlowCoordinator` | **ya** | sejak awal |
| `PendingFlow.transfer(...)` | **ya** | sejak awal (10 baris, boleh menumpang di file yang sama) |
| `TransferRoute` + `Step` | tidak | tujuan sudah lebih dari dua, atau butuh `goBack(to:)` |
| `TransferRouting` | tidak | layar perlu meminta pindah tanpa tahu coordinator-nya |
| `TransferScreenFactories` | tidak | ingin coordinator berhenti tahu cara membangun layar tujuan |
| `TransferLandingFactory` | tidak | layar landing punya **dua** pemanggil — flow baru dan coordinator lama |
| `…+Journey`, `…+Setup`, `…+RowActions`, `…+Destinations` | tidak | file induknya melewati 250 baris |

Empat file terakhir itu **bukan kode baru** — isinya dipindah apa adanya dari
file yang sudah ada, semata karena batas panjang file. Kalau di proyek Anda
batasnya berbeda, empat file itu tidak perlu ada.

Jadi hitungan yang sebenarnya untuk memulai: **satu file baru, dua baris
diganti.** Sisanya tumbuh saat ada yang menuntutnya, bukan sebelumnya.

---

## Template untuk flow berikutnya

Kodenya ada, siap salin: [`Examples/NewFeature/`](../Examples/NewFeature/).

Yang wajib per flow adalah **satu file** — class coordinator-nya plus
pendaftarannya ke `PendingFlow` di bagian bawah. Tujuan dibangun sebagai method
privat, perpindahannya `navigator.push`. Tidak ada enum rute, tidak ada struct
factory. Untuk sebagian besar flow, itu bentuk akhirnya.

[README template-nya](../Examples/NewFeature/README.md) memuat tabel kapan
masing-masing tambahan mulai perlu, dan empat hal yang paling sering keliru saat
mengisinya.

### Kenapa `Examples/TransferFeature/Flow/` punya lima file

Supaya jelas dan tidak dijadikan patokan:

- `TransferRoute` ada karena transfer punya **sembilan** tujuan dan butuh masuk
  ke tengah. Flow tiga layar tidak butuh itu.
- `TransferScreenFactories` ada karena **saya belum pernah melihat** ketujuh
  layar tujuannya, jadi coordinator-nya harus bisa dibangun tanpa mereka. Kalau
  Anda menulis flow sendiri, layar-layarnya ada di tangan Anda — jadikan method
  privat, dan file ini tidak perlu ada.
- `+Journey` dan `TransferFlowMount` terpisah karena batas 250 baris.

Dari lima file itu, yang benar-benar melekat pada "sebuah flow" hanya
coordinator dan pendaftarannya.

---

## Perilaku swipe-back, supaya tidak ada kejutan

Tiga situasi, dan ketiganya berbeda. Ini yang paling sering ditanyakan lebih
dulu karena langsung terasa penggunanya.

### 1. Di dalam flow UIKit, termasuk ke layar SwiftUI yang di-push

```swift
navigator.push(Screen { SomeScreen(viewModel: createSomeViewModel()) })
```

Swipe-back **jalan**, dan kembali ke layar UIKit sebelumnya. Layar itu bukan
"navigasi SwiftUI" — ia view SwiftUI yang duduk di tumpukan UIKit, jadi
gesturnya gestur UIKit yang biasa. Tidak ada yang perlu disiapkan selain dua
hal: layarnya tidak boleh membawa `NavigationView` sendiri, dan tombol back-nya
memanggil `goBackOrFinish()`, bukan `presentationMode.dismiss()`.

### 2. Ke pulau SwiftUI (`pushIsland`), yaitu rangkaian lama yang belum diurai

Ada dua tumpukan yang bertumpuk, jadi jawabannya bergantung posisi:

| Posisi | Swipe-back |
|---|---|
| Sedang di layar pertama pulau | keluar dari pulau, kembali ke layar UIKit sebelumnya |
| Sudah masuk lebih dalam di pulau | mundur satu langkah **di dalam** pulau |

`FlowNavigationController` memilih di antara keduanya dengan memeriksa
kedalaman `NavigationView` di dalam pulau. Pemeriksaan itu **best effort** —
ia mengandalkan `NavigationView` iOS 13–14 yang ditopang `UINavigationController`
di hierarki child. Kalau tidak ditemukan, gestur luar dimatikan dan pengguna
harus memakai tombol back. Pilihan itu disengaja: swipe yang tidak bereaksi
masih bisa diselamatkan tombol back, mundur dua langkah tanpa disadari tidak.

**Ini alasan lain untuk memakai pulau sesedikit mungkin.** Layar yang di-push
biasa (situasi 1) tidak punya kerumitan ini sama sekali.

### 3. Dari flow transfer kembali ke Dashboard

**Tidak ada swipe-back**, dan itu disengaja. Flow-nya dipresentasikan
`.fullScreen`, bukan sheet, supaya transaksi yang sedang disusun tidak bisa
ditinggalkan di tengah lewat jalur yang tidak Anda kendalikan. Satu-satunya
jalan keluar adalah tombol back di layar pertama flow, yang memanggil
`goBackOrFinish()` → `finish()`.

Kalau untuk flow lain nanti Anda justru **ingin** bisa di-swipe tutup, itu
ganti `modalPresentationStyle` di `FlowPresenter`, bukan perubahan arsitektur.

---

## Kapan `AppRouter`, kapan `navigator.push`

Pembagian ini menentukan, dan salah menempatkannya menghasilkan kegagalan yang
membingungkan.

| | Dipakai untuk | Bentuknya di layar |
|---|---|---|
| `AppRouter.shared.start(...)` | **masuk ke sebuah flow** dari dunia SwiftUI | modal `.fullScreen` |
| `navigator.push(...)` | berpindah **di dalam** flow yang sudah tampil | push, seperti biasa |

Sekali sebuah flow tampil, memanggil `AppRouter.shared.start` lagi tidak
menampilkan apa pun — hanya ada satu flow pada satu waktu. Dulu itu gagal
diam-diam; sekarang `assertionFailure` di Debug.

### Konsekuensi yang perlu diputuskan lebih dulu: animasinya berbeda

Masuk flow adalah presentasi modal, jadi layarnya **naik dari bawah**, bukan
menggeser dari kanan seperti push. Untuk Dashboard → Transfer itu wajar dan
lazim. Tetapi kalau Anda memindahkan banyak layar kecil satu per satu, tiap
layar jadi modal dan aplikasinya terasa berbeda.

Karena itu: **pindahkan per flow, bukan per layar.** Sebuah flow adalah
perjalanan berisi beberapa langkah. Layar daun tunggal yang dibuka dari
Dashboard sebaiknya tetap di `NavigationView` sampai flow yang memuatnya ikut
dipindah.

Kalau nanti ada flow yang animasinya harus tetap menggeser dari kanan, itu bisa
dengan `UIViewControllerTransitioningDelegate` sendiri — tetapi putuskan
sebelum memindahkan, bukan sesudah.

---

## Mundur ke langkah yang Anda tentukan

A → B → C → D, lalu dari D kembali ke B:

```swift
routing.goBack(to: .transactionAmount)
```

Menyebut **nama langkahnya**, bukan berapa kali mundur. Itu disengaja:
hitungan mundur rapuh, karena begitu ada langkah bersyarat yang kadang ikut
kadang tidak — dan flow transfer penuh dengan itu, lihat `startValasJourney` —
angkanya salah, dan salahnya baru terlihat di tangan pengguna.

Penandanya dipasang otomatis. `start(_:)` menandai tiap layar dengan
`route.step`, jadi tidak ada yang perlu diingat saat mendorong. Kalau nama yang
dituju tidak ada di tumpukan, `assertionFailure` di Debug — bukan diam saja.

Kalau ada dua layar bernama sama di tumpukan, yang dituju yang terdekat dengan
layar sekarang.

Menambah langkah baru: tambahkan case-nya di `TransferRoute`, tambahkan
padanannya di `TransferRoute.Step`, selesai. Kompilernya menagih keduanya.

---

## Bolak-balik SwiftUI dan UIKit di tengah flow

Bisa, dan sebetulnya itu memang bentuk normalnya — asal jelas dulu apa yang
berselang-seling.

**Yang berselang-seling adalah isi layarnya, bukan sistem navigasinya.** Di
dalam sebuah flow hanya ada **satu** tumpukan, milik `UINavigationController`.
Isi tiap layarnya SwiftUI. Jadi tumpukan seperti ini normal dan tanpa
kerumitan apa pun:

```
[ landing (SwiftUI baru) ]
[ amount  (SwiftUI lama, di-push biasa) ]
[ pulau   (rangkaian SwiftUI lama dengan NavigationView-nya) ]
[ summary (SwiftUI baru) ]
```

Ketiga cara mendorongnya berdampingan bebas:

```swift
navigator.push(screen, stepIdentifier: "amount")           // layar tunggal
navigator.pushIsland(coordinatorLama, stepIdentifier: "x") // rangkaian lama
```

dan untuk tumpukan awal, `setStack` bisa mencampur keduanya lewat
`createController(for:stepIdentifier:)` dan
`createIslandController(for:stepIdentifier:)`. Jadi masuk ke tengah pun tetap
mungkin walau sebagian langkahnya belum dipindah.

`goBack(to:)` menembus semuanya, termasuk melewati pulau, karena yang dibaca
penanda langkah — bukan jenis layarnya.

### Yang tidak bisa, dan sebaiknya tidak dicoba

Yang **tidak** boleh berselang-seling adalah **sistem navigasinya**: flow modal
di dalam flow modal. `AppRouter` hanya menyimpan satu `pendingFlow`, jadi itu
sudah ditolak dengan `assertionFailure` — dan penolakan itu memang tujuannya.
Begitu ada dua tumpukan modal, "tutup layar ini" berhenti punya jawaban tunggal.

Satu catatan tentang pulau: setelah keluar dari pulau lalu masuk lagi, pulaunya
masih di tumpukan yang sama, jadi kedalaman internalnya masih seperti
ditinggalkan. Biasanya itu yang diinginkan; kalau tidak, pulau itu sudah harus
jadi flow tersendiri.

---

## `LazyNavigationLink` — masih dipakai, tapi bukan di sini

Di dalam flow UIKit ia **tidak diperlukan sama sekali**. `navigator.push`
membangun layar tujuan pada saat berpindah; itu sudah lazy yang sesungguhnya,
tanpa cache, tanpa `@State`, tanpa penanda dua tahap.

Tetapi **jangan dihapus.** Ia masih menopang setiap layar yang belum dipindah —
dan untuk beberapa waktu ke depan itu sebagian besar aplikasi. Perbaikan
pelepasan cache di dalamnya juga masih berlaku di sana.

Jadi: berhenti memakainya di flow yang sudah dipindah, biarkan bekerja di
sisanya.

---

## Yang sudah ada dan yang harus Anda sediakan

| Sudah ada di repo | Harus Anda sediakan |
|---|---|
| `AppRouter`, `PendingFlow`, `.mountFlowRouter()` | pemasangan `.mountFlowRouter()` di Main |
| `FlowNavigator`, `FlowNavigationController`, `FlowPresenter` | — |
| `TransferRoute`, `TransferRouting` | — |
| `TransferFlowCoordinator` + percabangannya | — |
| `TransferLandingFactory` (layar landing lengkap) | nama property aksi back yang benar |
| `TransferScreenFactories` (bentuknya) | `TransferScreenFactories.live` — tujuh closure |

Tiga hal, itu saja.

---

## Langkah 1 — pasang router-nya

Di view **paling luar** Main, di luar `NavigationView`:

```swift
struct MainView: View {
    var body: some View {
        NavigationView {
            DashboardCoordinator()
        }
        .mountFlowRouter()
    }
}
```

Prelogin tidak disentuh.

---

## Langkah 2 — sediakan tujuh factory, isinya kosong dulu

Sengaja kosong. Tujuannya membuktikan alasnya jalan sebelum ada yang dipindah.

```swift
extension TransferScreenFactories {
    static let live = TransferScreenFactories(
        createNewRecipient: { _, _ in AnyView(EmptyView()) },
        createTransactionAmount: { _ in AnyView(EmptyView()) },
        createDebitAccountSelection: { _ in AnyView(EmptyView()) },
        createCurrencySelection: { _ in AnyView(EmptyView()) },
        createCountrySelection: { _ in AnyView(EmptyView()) },
        createTelegraphicRecipientForm: { _ in AnyView(EmptyView()) },
        createBankSummary: { _ in AnyView(EmptyView()) }
    )
}
```

---

## Langkah 3 — perbaiki satu baris di `TransferLandingFactory`

Di `setupBackAction` saya menulis `viewModel.navigationBarViewModel.onTapBackButton`.
Nama itu **tebakan** — saya belum pernah melihat isi `NavigationBarViewModel`.
Ganti dengan nama yang sebenarnya. Yang penting aksinya memanggil
`routing.onRequestBack(viewModel)`, bukan menutup layar sendiri.

Kalau tombol back ditangani `Screen` lewat `@Environment(\.presentationMode)`,
itu harus diganti untuk layar di dalam flow: `presentationMode.dismiss()` di
dalam `UIHostingController` yang di-push tidak mem-pop tumpukannya.

---

## Langkah 4 — ganti cara Dashboard membuka transfer

```swift
// sebelumnya: selectionCoordinatorName = TransferLandingCoordinator.named
AppRouter.shared.start(
    .transfer(.landing(transferCart: TransferCart(), category: .idr))
)
```

`TransferLandingCoordinator` yang lama **dibiarkan** di tempatnya. Ia masih
dipakai jalur lain, dan menjadi pembanding kalau ada perilaku yang berbeda.

---

## Langkah 5 — uji alasnya, sebelum memindahkan apa pun

Ini titik keputusannya. Kalau ada yang gagal di sini, gagalnya murah.

1. Buka transfer dari Dashboard. Daftar penerima harus muncul dan memuat IDR.
2. `UIHostingController` iOS 13 — periksa safe area atas dan bawah, keyboard
   saat mengetik di kolom pencarian, dan bar SwiftUI Anda tampil normal.
3. Ganti tab ke Valas dan Proxy. Daftarnya harus berganti.
4. Ketik di pencarian. Daftarnya harus berganti.
5. Tekan back. Harus kembali ke Dashboard, dan Dashboard utuh seperti
   ditinggalkan.
6. Pasang `LifecycleProbe` di `TransferLandingViewModel` dan
   `TransferFlowCoordinator`. Buka–tutup tiga kali, lalu:

```swift
LifecycleTracker.shared.logSnapshot()
```

Yang dicari: `INIT` dan `DEINIT` berpasangan, dan snapshot-nya kosong setelah
kembali ke Dashboard.

Kalau keenamnya lolos, keputusan navigasinya terbukti di aplikasi Anda, bukan
hanya di atas kertas.

---

## Langkah 6 — isi factory satu per satu

Urutan yang paling hemat: **ikuti satu jalur transaksi sampai selesai**, jangan
mengisi tujuh-tujuhnya sekaligus. Jalur IDR ke penerima tersimpan adalah yang
paling sering dipakai, dan hanya melewati `createTransactionAmount`.

Untuk tiap tujuan, dua pilihan:

**a. Sudah punya waktu memindahkannya** — buat factory-nya seperti
`TransferLandingFactory`: bangun UseCase dan `input`-nya, bangun ViewModel,
sambungkan, kembalikan layarnya. Nilai yang dibutuhkan dibaca dari
`useCase.output` memakai ekspresi yang sama persis dengan yang ada di
`TransferLandingCoordinator+Destinations.swift` hari ini.

**b. Belum** — pakai jembatan sementara:

```swift
createTransactionAmount: { useCase in
    AnyView(
        FlowIslandPlaceholder(useCase: useCase)   // bungkus coordinator lama
    )
}
```

atau langsung `navigator.pushIsland(CoordinatorLama(...))` dari coordinator.
Ingat batasan swipe-back pulau di atas, dan bahwa pulau bukan tujuan akhir.

Setelah satu jalur utuh jalan, tambahkan test kebocoran untuk ViewModel-nya —
bentuknya sama dengan `testFactoryBuiltViewModelIsReleased`.

---

## Gaya Transfer Landing bisa dipakai sekarang, tanpa menunggu navigasi

Ini bagian yang paling sering tertunda tanpa alasan. Semua yang kita kerjakan di
`TransferLandingViewModel` **tidak bergantung pada keputusan navigasi** dan
berlaku sama di kedua dunia:

- `[weak self]` di setiap closure yang disimpan, termasuk yang dipasang sebagai
  referensi method.
- Membangun daftar ke array lokal, terbitkan sekali.
- Cache baris supaya identitasnya bertahan antar halaman.
- `input` ditulis sekali saat konstruksi, tidak pernah disentuh lagi.
- Penjagaan nilai sebelum `objectWillChange.send()`.
- Pembangunan layar dikeluarkan menjadi factory.
- Test `trackForMemoryLeaks` untuk tiap ViewModel dan UseCase.

Kerjakan itu di layar mana pun yang kebetulan Anda sentuh, sekarang. Kalau
keputusan navigasinya nanti berubah, tidak ada satu pun dari daftar ini yang
terbuang.

Yang **harus** menunggu hanyalah yang menyebut tujuan: `onCreateNavigationLinks`,
`LazyNavigationLink`, dan penanda dua tahap. Ketiganya load-bearing sampai
penggantinya terbukti jalan.

---

## Yang tidak berubah sama sekali

Supaya jelas seberapa besar cakupannya:

- Seluruh `ViewModel` dan `UseCase`, termasuk `TransferLandingViewModel` yang
  baru kita bersihkan.
- Aturan `input` / `output` / `repository` / `callback`.
- Layar-layarnya sendiri — `TransferLandingScreen` tidak disentuh.
- Prelogin.
- Semua flow lain yang masih memakai `NavigationView`.

Yang berubah hanya **siapa yang memutuskan perpindahan**, dan itu pindah dari
pohon view ke sebuah objek.
