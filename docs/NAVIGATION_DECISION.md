# Keputusan navigasi, dan bentuk flow yang menyusul dari sana

Dokumen ini menjawab empat pertanyaan sekaligus, karena jawabannya satu:
bagaimana bentuk coordinator, bagaimana navigasinya, apakah
`onCreateNavigationLinks` dibuang, dan apa yang sebenarnya menentukan fps.

Ditulis setelah satu layar penuh — Transfer Landing — dikerjakan sampai jalan.
Jadi ini bukan preferensi; ini kesimpulan dari daftar masalah yang benar-benar
kita temui.

---

## Yang kita pelajari dari Transfer Landing

Layar itu butuh **empat** mekanisme yang tidak ada hubungannya dengan urusan
transfer, semata supaya perpindahan halamannya bekerja:

| Mekanisme | Sebenarnya menambal apa |
|---|---|
| `.id(destinationCoordinatorName)` | `NavigationView` iOS 13–14 tidak melakukan push untuk tautan yang disisipkan dalam keadaan sudah terpilih |
| Penanda tujuan **dua tahap** | Hal yang sama, setelah `.id()` dilepas |
| Penanda disimpan di ViewModel, bukan coordinator | `LazyNavigationLink` membekukan destination, jadi `@State` coordinator tidak terlihat oleh layar yang ter-push |
| Pelepasan cache saat selection lepas | Destination yang dibekukan menjadi pemilik ViewModel, dan umurnya mengikuti layar **induk** |

Perhatikan kolom kanan. Tidak satu pun berbunyi "karena arsitektur MVVM +
Coordinator Anda salah". Semuanya berbunyi "karena `NavigationView`".

Arsitektur lapisan Anda sehat. Yang tidak sehat adalah alasnya.

Dan masalahnya berlipat mengikuti percabangan: Transfer Landing punya sembilan
tujuan. Setiap layar bercabang di aplikasi Anda akan menemukan keempat hal itu
lagi, satu per satu, dengan variasi yang berbeda-beda.

---

## Keputusan

**Navigasi di dalam sebuah flow memakai `UINavigationController` +
`UIHostingController`. Coordinator menjadi class biasa, bukan `View`.**

`NavigationView` tetap di tempatnya untuk semua yang belum dipindah. Keduanya
berdampingan per flow, dan titik temunya tepat satu — lihat "Cara berdampingan".

### Kenapa ini yang menjawab ketiga tujuan Anda

**Bebas kebocoran.** `pop` melepas `UIHostingController`, yang melepas
`rootView`, yang melepas ViewModel. Deterministik, tanpa perlu tahu kapan
`NavigationView` memutuskan merobohkan subtree. Probe Anda akan mencetak INIT
dan DEINIT berpasangan, dan checkpoint di root menjadi jawaban ya/tidak yang
sebenarnya.

**Navigasi ringan.** Tidak ada `NavigationLink` di dalam `body` mana pun. Tidak
ada `AnyView` tujuan. Tidak ada kamus atau `switch` tujuan yang dievaluasi
ulang. Tidak ada `LazyNavigationLink`, `.id()`, atau penanda dua tahap. Layar
tujuan dibangun **pada saat** berpindah — itu definisi lazy yang sesungguhnya,
bukan hasil akal-akalan.

**fps.** Ini yang paling sering disalahpahami, jadi lihat bagian fps di bawah:
navigasi bukan penyebab utamanya, tapi ia menyumbang lewat `AnyView` di setiap
`body` dan lewat objek yang menumpuk.

Bonusnya yang tidak ada padanannya di `NavigationView`: `popToRoot`, mundur ke
layar tertentu (`popTo(stepsBack:)`), dan deeplink yang tinggal menyusun
tumpukan. Flow transaksi butuh ketiganya.

### Yang harus jujur disebut sebagai biaya

- Layar di dalam flow harus **berhenti memakai `NavigationView`**. Kalau ada
  layar yang menaruh `NavigationView` sendiri di dalamnya, itu jadi nested dan
  harus dilepas.
- Bar navigasi UIKit disembunyikan dan bar SwiftUI Anda yang dipakai — ini
  justru menguntungkan, tapi gestur swipe-back perlu dikembalikan secara
  eksplisit. Sudah ditangani di `FlowNavigationController`.
- `UIHostingController` di iOS 13 punya perilaku safe-area dan keyboard yang
  berbeda dari iOS 14+. **Ini yang harus dibuktikan lebih dulu**, sebelum
  memindahkan layar kedua.
- State layar tidak lagi bertahan saat pop. Itu memang yang kita inginkan, tapi
  kalau ada flow yang diam-diam mengandalkannya, perilakunya berubah.

---

## Bentuk coordinator

Coordinator menjadi class yang memegang `FlowNavigator` dan tahu urutan
langkahnya. Bentuknya:

```swift
final class TransferFlowCoordinator {
    private let navigator: FlowNavigator
    private let transferCart: TransferCart

    init(navigator: FlowNavigator, transferCart: TransferCart) {
        self.navigator = navigator
        self.transferCart = transferCart
    }

    /// Layar pertama. Mengembalikan view, bukan melakukan efek samping, supaya
    /// `FlowPresenter` yang memasangnya ke tumpukan — lihat bagian
    /// "Persimpangan" untuk bentuk yang menerima entry point.
    func makeLanding() -> some View {
        Screen {
            TransferLandingScreen(viewModel: makeLandingViewModel())
        }
    }

    private func makeLandingViewModel() -> TransferLandingViewModel {
        let useCase = TransferLandingUseCase()
        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart

        let viewModel = TransferLandingViewModel()
        viewModel.setUseCase(useCase)

        // Menggantikan `onCreateNavigationLinks` sepenuhnya.
        useCase.callback.onSubmissionSucceed = { [weak self, weak useCase] in
            guard let useCase = useCase else { return }
            self?.routeAfterLanding(useCase.output)
        }

        return viewModel
    }

    private func routeAfterLanding(_ output: TransferLandingUseCase.Output) {
        if output.transferCategory == .privateAccount {
            navigator.push(makeDebitAccountSelection(output))
            return
        }

        navigator.push(makeTransactionAmount(output))
    }
}
```

Tiga hal yang berubah dan semuanya penyederhanaan:

**Perutean menjadi kode biasa.** `routeAfterLanding` adalah `if`/`else` yang
bisa dibaca dan di-unit-test tanpa SwiftUI sama sekali. Bandingkan dengan
`startDestinationCoordinator` + `startDestination` dua tahap + `switch` sembilan
cabang + `createXxx` sembilan buah yang ada sekarang. Semua itu hilang.

**Nilai dioper lewat inisialiser, bukan `Binding`.** Anda pernah bertanya apakah
memakai `useCase.output` sebagai binding yang ditunggu layar berikutnya itu
pendekatan yang baik. Jawabannya: rantai `Binding` antar coordinator itu ada
**hanya karena** layar tujuan harus sudah berdiri sebelum dipakai. Begitu tujuan
dibangun pada saat berpindah, tidak ada yang perlu ditunggu — nilainya sudah
final saat Anda memanggil `push`. Seluruh rantai `didSet` antar layar hilang,
dan dengan itu hilang juga satu kelas bug yang sulit dilacak.

**Coordinator punya pemilik yang jelas.** Ia dipegang oleh flow, hidup selama
flow, dan mati saat flow ditutup. Bukan struct yang di-init ulang setiap
evaluasi body.

---

## `onCreateNavigationLinks` — dibuang, tapi bukan sekarang

Jawaban singkatnya ya, ia hilang seluruhnya. Bersama `destinationCoordinatorName`,
penanda dua tahap, `LazyNavigationLink`, `.id()`, dan `AnyView` tujuan di setiap
`body`.

Tetapi **jangan dilepas sebelum penggantinya terbukti.** Ia load-bearing hari
ini; kita sudah membuktikan itu dengan cara yang mahal saat `.id()` dilepas dan
navigasi berhenti total. Urutannya: bangun flow UIKit di samping yang lama,
buktikan dengan dua layar, baru lepas yang lama.

Selama masa transisi, `ScreenContentViewModel` tetap punya
`onCreateNavigationLinks`. Layar di dalam flow baru cukup tidak mengisinya —
nilai defaultnya mengembalikan view kosong, jadi tidak ada biaya.

---

## Cara berdampingan

Satu titik temu per flow, dan Dashboard tidak berubah bentuk:

```swift
@State private var isTransferFlowPresented = false

// di dalam body Dashboard
.background(
    FlowPresenter(isPresented: $isTransferFlowPresented) { navigator in
        TransferFlowCoordinator(
            navigator: navigator,
            transferCart: transferCart
        )
        .stack(enteringAt: .landing)
    }
)
```

Tombol transfer menyalakan `isTransferFlowPresented`. Selesai. Flow lain yang
masih memakai `NavigationLink` tidak tersentuh, dan tidak ada layar yang harus
tahu keduanya ada.

Presentasinya `.fullScreen` lewat UIKit. `.fullScreenCover` baru ada di iOS 14,
dan sheet iOS 13 bisa ditutup dengan swipe kapan saja — flow transaksi tidak
boleh bisa ditinggalkan di tengah lewat jalur yang tidak Anda kendalikan.

---

## Memasangnya di aplikasi Anda

Struktur sekarang: `NavigationView` ada di Main dan di Prelogin; Main berisi
Dashboard; Dashboard membuka Transfer Landing.

**Prelogin tidak tersentuh sama sekali.** Yang berubah hanya satu tempat.

### Di mana dipasang

Di view **paling luar** Main, di luar `NavigationView`-nya:

```swift
struct MainView: View {
    var body: some View {
        NavigationView {
            DashboardCoordinator()
        }
        .mountTransferFlow(screenFactories: transferScreenFactories)
    }
}
```

Di luar, bukan di dalam Dashboard, karena dua alasan. Pertama, flow-nya jadi
bisa dibuka dari tab mana pun dan dari layar mana pun — termasuk layar yang
sedang tampil di atas Dashboard. Kedua, `FlowPresenter` mempresentasikan dari
view controller tempat ia menempel; kalau ia menempel pada layar yang bisa
hilang dari pohon, presentasinya bisa tertunda tanpa pernah terjadi.

### Bagaimana Dashboard membukanya

Tombol transfer di Dashboard tidak lagi menyalakan
`selectionCoordinatorName`, melainkan:

```swift
transferFlowEntry.start(
    .landing(transferCart: TransferCart(), category: .idr)
)
```

Tidak ada `@State`, tidak ada `Binding`, tidak ada `NavigationLink` yang harus
berdiri lebih dulu di pohon Dashboard. Dan karena `transferFlowEntry` global,
layar lain nanti bisa memakai baris yang sama persis.

### Apa yang terjadi pada Dashboard selama flow tampil

Ia tetap ada, hanya tertutup. Saat flow ditutup, Dashboard kembali **persis
seperti ditinggalkan** — posisi scroll, tab yang aktif, semuanya. Ini justru
lebih baik daripada sekarang, karena `NavigationView` di iOS 13 tidak
menjamin itu.

### Satu hal yang berubah perilakunya: tombol back layar pertama

Di `NavigationView`, Transfer Landing punya induk di tumpukan yang sama, jadi
back berarti mundur ke Dashboard. Sebagai layar pertama tumpukan modal, tidak
ada yang bisa dimundur — back harus **menutup flow**.

Karena itu `TransferLandingFactory.Routing` punya `onRequestBack`, dan
nilainya berbeda di kedua dunia: `selectionCoordinatorName = nil` di
`NavigationView`, `goBackOrFinish()` di flow. `goBackOrFinish()` memilih
sendiri berdasarkan posisi layar, jadi layar yang sama bisa dipakai sebagai
layar pertama maupun layar tengah tanpa diubah.

Kalau tombol back di proyek Anda ditangani `Screen` lewat
`@Environment(\.presentationMode)`, itu **harus** diganti untuk layar di dalam
flow: `presentationMode.dismiss()` di dalam `UIHostingController` yang di-push
tidak mem-pop tumpukannya.

### Uji sepuluh menit sebelum memindahkan apa pun

Urutannya sengaja: yang paling mungkin bermasalah diuji paling murah.

1. Pasang `.mountTransferFlow` dengan tujuh factory yang isinya masih
   `AnyView(EmptyView())`. Buka dari Dashboard dengan `.landing`.
2. Periksa yang bergantung pada `UIHostingController` iOS 13 — safe area di
   atas dan bawah, keyboard saat mengetik di kolom pencarian, dan bar SwiftUI
   Anda tampil normal.
3. Tekan back di landing. Harus kembali ke Dashboard dengan Dashboard utuh.
4. Pasang probe di `TransferLandingViewModel` dan `TransferFlowCoordinator`.
   Buka–tutup tiga kali. Yang dicari: INIT dan DEINIT berpasangan, dan
   `liveTypes()` kosong setelah kembali.

Kalau keempatnya lolos, sisanya tinggal mengisi factory satu per satu.

---

## Persimpangan: keluar-masuk antara dua dunia

Ini bagian yang paling menentukan apakah migrasi bertahap bisa berjalan, karena
di aplikasi berisi ratusan layar percabangannya tidak akan pernah rapi. Dua
arahnya punya jawaban yang berbeda, dan yang kedua justru lebih mudah.

### Aturan yang mendasari keduanya

**Presentasi untuk menyeberang dunia, push untuk bergerak di dalam flow.**

Sekali menyeberang per perjalanan pengguna. Kalau sebuah flow UIKit perlu flow
UIKit lain, ia mendorong layar flow itu ke navigator-nya sendiri — bukan
mempresentasikannya. Tumpukan modal yang bertingkat-tingkat adalah bagaimana
migrasi bertahap berubah menjadi kekacauan yang tidak bisa dibaca siapa pun.

### Arah 1 — dari tengah flow UIKit, masuk ke layar SwiftUI

Tiga bentuk, urut dari yang paling dianjurkan.

**a. Layarnya daun — dorong layarnya saja.** Ini yang paling sering, dan paling
murah. Yang Anda butuhkan dari dunia SwiftUI hanyalah **layar beserta ViewModel
dan UseCase-nya**; coordinator-nya tidak dibutuhkan sama sekali, karena
coordinator itu semata mesin navigasi.

```swift
private func showRecipientDetail(_ contact: BankContact) {
    navigator.push(
        Screen {
            RecipientDetailScreen(viewModel: makeRecipientDetailViewModel(contact))
        }
    )
}
```

Layarnya tidak diubah. Coordinator SwiftUI-nya tetap berdiri untuk flow lain
yang masih memakainya.

Yang perlu dijaga: pembangunan ViewModel-nya sekarang ada di dua tempat —
coordinator lama dan coordinator baru. Jangan disalin. Keluarkan menjadi satu
factory yang dipanggil keduanya. Langkah itu bagus dikerjakan lebih dulu,
sebelum migrasi apa pun, karena ia berguna di kedua dunia.

**b. Rangkaiannya utuh dan belum bisa diurai — dorong sebagai pulau.**
`navigator.pushIsland(...)` membungkusnya dalam `NavigationView` sendiri, dan
seluruh rangkaian itu menjadi **satu** entri di tumpukan UIKit.

```swift
navigator.pushIsland(
    ExistingSubFlowCoordinator(
        selectionCoordinatorName: .constant(ExistingSubFlowCoordinator.named),
        sourceCoordinatorName: .constant(nil),
        transferCart: transferCart
    )
)
```

Di dalam pulau, `NavigationLink` bekerja seperti biasa. Keluar dari pulau
berarti keluar seluruhnya — tidak ada cara mundur ke langkah ke-2 dari luar.
Karena itu **pulau harus kecil.** Kalau sebuah rangkaian perlu dimasuki kembali
di tengah, ia bukan pulau; ia flow tersendiri dan harus dipindah.

Satu detail yang sudah ditangani `FlowNavigationController`: gestur swipe-back
UIKit dimatikan selama pulau di atas, karena `NavigationView` di dalamnya punya
gesturnya sendiri dan dua-duanya aktif berarti satu swipe memundurkan dua
tingkat.

**c. Pulau perlu mengembalikan hasil.** Berikan closure ke coordinator pulaunya,
persis seperti closure lain:

```swift
navigator.pushIsland(
    BankSelectionCoordinator(transferCart: transferCart) { [weak self] bank in
        self?.navigator.pop()
        self?.continueAfterBankSelection(bank)
    }
)
```

Pulau tidak perlu tahu ia sedang berada di dalam flow UIKit. Ia hanya melapor.

### Arah 2 — dari tengah flow SwiftUI, masuk ke tengah flow transfer

Ini yang justru **lebih mudah**, dan `NavigationView` tidak punya padanannya
sama sekali.

`FlowPresenter` tidak meminta layar pertama; ia meminta **seluruh tumpukan**.
Jadi masuk ke tengah bukan urusan mendorong beberapa layar berturut-turut,
melainkan menyatakan tumpukan akhirnya:

```swift
extension TransferFlowCoordinator {
    enum Entry {
        case landing
        case transactionAmount(RecipientAccount)
        case summary(TransferDraft)
    }

    func stack(enteringAt entry: Entry) -> [UIViewController] {
        switch entry {
        case .landing:
            return [navigator.controller(for: makeLanding())]

        // Back membawa ke landing — pengguna bisa mengganti penerima.
        case .transactionAmount(let recipient):
            return [
                navigator.controller(for: makeLanding()),
                navigator.controller(for: makeTransactionAmount(recipient))
            ]

        // Back keluar dari flow — ringkasan tidak boleh diedit mundur.
        case .summary(let draft):
            return [navigator.controller(for: makeSummary(draft))]
        }
    }
}
```

Layar SwiftUI mana pun cukup menyalakan `Bool` dan menyebut entry-nya. Ia tidak
perlu tahu apa pun tentang isi flow transfer.

Perhatikan bahwa **coordinator yang menentukan tombol back membawa ke mana**,
dan itu keputusan produk, bukan keputusan teknis. Di `NavigationView` keputusan
itu tidak bisa dinyatakan sama sekali — tumpukannya adalah apa pun yang
kebetulan terbentuk dari rangkaian tautan yang dilalui.

### Arah 3 — kembali ke dunia SwiftUI setelah flow selesai

Jangan biarkan flow menutup dirinya sendiri lalu berharap layar pemanggil
menebak apa yang terjadi. Pisahkan dua hal: **penutupan** dan **hasil**.

`navigator.finish()` mengurus penutupannya, lewat `isPresented`. Hasilnya
dilaporkan closure yang Anda serahkan ke coordinator saat membuatnya:

```swift
FlowPresenter(isPresented: $isTransferFlowPresented) { navigator in
    TransferFlowCoordinator(
        navigator: navigator,
        transferCart: transferCart,
        onComplete: { receipt in
            transferReceipt = receipt      // @State di layar SwiftUI
            navigator.finish()
        }
    )
    .stack(enteringAt: .landing)
}
```

Arah datanya tetap satu arah, dan layar SwiftUI-lah yang memutuskan apa yang
terjadi setelahnya — pindah tab, menampilkan struk, atau sekadar menutup.

### Yang sebaiknya tidak dilakukan

- **Mempresentasikan flow dari dalam flow.** Kalau transfer perlu masuk ke flow
  lain, dorong layarnya, atau jadikan pulau. Modal di atas modal membuat
  `dismiss` menjadi tebakan.
- **Pulau yang besar.** Begitu Anda ingin "mundur ke langkah ke-3 di dalam
  pulau", pulau itu sudah harus jadi flow.
- **Menyalin pembangunan ViewModel** dari coordinator lama ke coordinator baru.
  Keluarkan menjadi factory bersama lebih dulu.

---

## Factory: satu layar, dua pemanggil

Langkah pertama yang nyata, dan satu-satunya yang berguna apa pun keputusan
navigasi akhirnya. Contohnya sudah ada:
[`TransferLandingFactory`](../Examples/TransferLanding/TransferLandingFactory.swift).

Garis pemisahnya satu kalimat: **apa pun yang tidak menyebut tujuan, masuk
factory.** UseCase beserta `input`-nya, judul, analytic, penyambungan ViewModel
ke UseCase. Yang menyebut tujuan diserahkan pemanggil lewat `Routing`.

Setelah dipisah, `TransferLandingCoordinator` tinggal berisi perutean dan
`onCreateNavigationLinks`. Coordinator flow UIKit memakai factory yang sama:

```swift
private func makeLanding() -> some View {
    TransferLandingFactory(transferCart: transferCart).makeScreen(
        routing: TransferLandingFactory.Routing(
            onRequestNewRecipient: { [weak self] viewModel in
                self?.showNewRecipient(viewModel.selectedTransferCategory)
            },
            onSubmissionSucceed: { [weak self] viewModel in
                self?.routeAfterLanding(viewModel.useCase.output)
            }
        )
    )
}
```

Bandingkan dengan versi `NavigationView`-nya: yang berbeda hanya isi kedua
closure. Layar, ViewModel, UseCase, judul, dan analytic-nya identik — dan
identik karena memang objek yang sama, bukan karena dijaga agar mirip.

### Satu aturan yang harus dipatuhi closure `Routing`

**Jangan menangkap ViewModel-nya.** Ia datang sebagai parameter justru supaya
tidak perlu ditangkap. Closure `Routing` berakhir tersimpan di
`useCase.callback`, dan ViewModel menyimpan UseCase — jadi closure yang
menangkap ViewModel menutup lingkaran, persis kelas kebocoran yang baru saja
kita bersihkan di layar ini.

Bentuk salahnya menggoda, karena `viewModel` biasanya sudah ada di scope
pemanggil:

```swift
onSubmissionSucceed: { _ in self.route(viewModel) }          // salah
onSubmissionSucceed: { viewModel in self.route(viewModel) }  // benar
```

`testFactoryBuiltViewModelIsReleased` merah untuk bentuk yang pertama, jadi
aturan ini menggagalkan sesuatu dan bukan sekadar tertulis di dokumen.

Kalau pemanggilnya sebuah class — coordinator flow UIKit — closure-nya tetap
perlu `[weak self]` untuk dirinya sendiri.

---

## Lapisan: ViewModel, UseCase, dan aturan input/output/repository

Aturan di [ACCESS_MATRIX.md](ACCESS_MATRIX.md) tidak berubah. Yang perlu
dipertegas hanya bagian yang benar-benar menggigit kita:

**`input` ditulis sekali, saat konstruksi.** Bug CVV kosong di Detail Card Info
lahir dari `input` yang ditulis coordinator sementara ViewModel membaca
`repository`, dan urutannya tidak dijamin. Perlakukan `input` sebagai argumen
inisialiser: diisi saat UseCase dibuat, tidak pernah disentuh lagi. Dengan
coordinator berbentuk class, ini menjadi wajar dengan sendirinya.

**`repository` milik UseCase, dan ViewModel tidak menjangkaunya langsung.**
Hari ini `TransferLandingViewModel` membaca `useCase.repository.transferCart`,
`useCase.repository.transferCategory`, dan seterusnya di banyak tempat. Setiap
satunya adalah pengetahuan ViewModel tentang isi perut UseCase. Berikan
computed property di UseCase, dan ViewModel membaca itu. Ini bukan soal
kerapian: saat bentuk repository berubah, yang ikut berubah menjadi satu file,
bukan sepuluh.

**`output` adalah hasil satu langkah, dibaca coordinator.** Bukan saluran
komunikasi antar layar. Coordinator membacanya saat langkahnya selesai, lalu
menyusun `input` langkah berikutnya. Dengan begitu tidak ada dua layar yang
menulis ke objek yang sama.

**`callback` tidak pernah dipanggil langsung dari UseCase.** Selalu lewat
helper di `UseCaseProtocol`, supaya jaminan main thread tidak bisa terlewat.
Ini sudah jadi aturan 10 di [SCREEN_PATTERN.md](SCREEN_PATTERN.md), dan di flow
yang lewat jaringan ia bukan lagi teoretis.

---

## fps 60 — urutan yang benar

Navigasi bukan penyebab utamanya. Urutan di bawah ini disusun berdasarkan
dampak, dan **tiga yang pertama tidak ada hubungannya dengan navigasi sama
sekali.**

**1. Invalidasi `ObservableObject` bersifat object-level.** Ini yang terbesar,
dan yang paling sering luput. Satu `@Published` berubah meng-invalidasi
**seluruh** layar yang mengamatinya — bukan bagian yang memakainya.
`@Observable` yang bersifat per-property baru ada di iOS 17, jadi di iOS 13
satu-satunya obat adalah memecah ViewModel: yang berubah sering dipisah dari
yang jarang berubah, dan sub-view mengamati sub-ViewModel-nya sendiri.

Tersangka paling konkret di aplikasi Anda: `scrollViewContainerSize` dan
`scrollViewContentSize` sebagai `@Published` di ViewModel yang sama dengan
seluruh isi layar. Keduanya berubah **setiap frame saat scroll**. Kalau tebakan
ini benar, setiap frame scroll meng-invalidasi seluruh layar, dan tidak ada
perbaikan lain yang akan menolong sebelum ini diperbaiki.

**2. List panjang di iOS 13.** Tidak ada `LazyVStack`. `ScrollView` + `VStack`
membangun **semua** baris, termasuk yang tidak terlihat. Untuk daftar penerima
yang bisa ratusan baris, jawabannya membungkus `UICollectionView` — dan begitu
navigasinya sudah UIKit, itu tidak lagi terasa asing di flow tersebut.

**3. `AnyView`.** Ia menghapus structural identity, sehingga SwiftUI kehilangan
kemampuan membandingkan pohon lama dan baru dan harus membangun ulang. Ada di
setiap layar Anda lewat `onCreateNavigationLinks`. Ini yang hilang gratis
sebagai efek samping keputusan navigasi.

**4. `.blur()` di akar setiap layar.** Perlu diukur — kalau ia memicu
offscreen rendering walau radiusnya nol, biayanya per frame.

**5. Objek yang menumpuk.** Bukan penyebab fps langsung, tapi memori yang tumbuh
mengikuti kedalaman navigasi berujung pada tekanan memori, dan tekanan memori
berujung pada frame yang jatuh.

Prosedur mengukur keempatnya ada di [MEASUREMENT_GUIDE.md](MEASUREMENT_GUIDE.md).
**Ukur dulu.** Dalam penelusuran ini saya empat kali menyimpulkan perilaku
runtime dari membaca kode dan empat kali keliru — `.id()`, penanda di
coordinator, `onStartFetchLoading`, dan arah penjagaan di `loadData()`.
Instruments tidak punya masalah itu.

---

## Urutan mengerjakannya

Satu flow dulu, dan **buktikan alasnya sebelum memindahkan isinya.**

1. **Buktikan seam-nya dengan layar paling sederhana di flow transfer.**
   Presentasikan flow berisi satu layar saja lewat `FlowPresenter`. Yang
   diperiksa: safe area benar, keyboard tidak menutupi field, swipe-back jalan,
   bar SwiftUI Anda tampil normal, dan menutup flow mengembalikan ke Dashboard
   dengan bersih. Kalau ada yang salah di `UIHostingController` iOS 13, di sini
   tempat menemukannya — bukan setelah sembilan layar dipindah.
2. **Tambahkan layar kedua**, cukup untuk membuktikan push dan pop. Pasang
   probe di kedua ViewModel. Yang dicari: INIT dan DEINIT berpasangan saat
   maju-mundur. Kalau ini hijau, keputusannya terbukti.
3. **Baru pindahkan Transfer Landing beserta sembilan tujuannya.** Perutean
   pindah dari `switch` di coordinator-view menjadi method di coordinator-class.
   ViewModel dan UseCase-nya tidak berubah sama sekali — seluruh perbaikan yang
   sudah kita lakukan tetap berlaku.
4. **Lepas `onCreateNavigationLinks` dari layar-layar flow itu**, dan bersamanya
   `LazyNavigationLink` untuk flow tersebut.
5. **Ukur fps sebelum dan sesudah**, di build Release, di device. Kalau
   angkanya tidak bergerak, tersangkanya nomor 1 dan 2 di daftar fps — dan
   keduanya bisa dikerjakan tanpa menunggu flow lain dipindah.

Yang tidak perlu ditunggu: perbaikan `[weak self]`, penerbitan tunggal untuk
daftar, `input` yang ditulis sekali, dan pemecahan ViewModel. Semuanya berlaku
di kedua dunia navigasi, dan semuanya bisa dikerjakan hari ini di layar mana
pun.
