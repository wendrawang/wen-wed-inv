# Kerangka aplikasi: root, tab, dan blocker

Menjawab tiga hal: apakah mengosongkan project lalu mulai dari nol itu bijak,
bentuk root splash/prelogin/main, dan di mana bottom sheet serta blocker
sebaiknya tinggal.

---

## 1. Mulai dari nol — premisnya perlu diluruskan dulu

**Bundle ID tidak terikat pada file project.** Ia sekadar build setting. Anda
bisa membuat project Xcode baru dan mengisinya dengan bundle identifier yang
sama persis — provisioning profile, sertifikat, dan record App Store Connect
mengikuti bundle ID, bukan `.xcodeproj`. Jadi alasan "nanti perlu daftar bundle
ID baru" tidak berlaku.

Tapi begitu premis itu hilang, pertanyaannya berubah — dan pertanyaan yang
sebenarnya bukan soal file project.

### Dua hal yang sedang tercampur

**(a) File project yang berantakan.** Build setting yang menyimpang antar
konfigurasi, build phase mati, `pbxproj` yang konflik terus. Ini nyata, dan
memperbaikinya **pekerjaan kecil** — sekitar satu minggu, tanpa menyentuh satu
baris kode aplikasi.

**(b) Kode yang ingin ditulis ulang.** Ini yang sebenarnya Anda inginkan, dan
ini yang berbahaya.

Menulis ulang aplikasi bank berisi ratusan layar sekaligus berarti berbulan-bulan
tanpa rilis. Sementara itu tetap ada patch keamanan, perubahan regulasi, dan
permintaan bisnis yang harus jalan — jadi dua basis kode dirawat bersamaan, dan
yang lama tetap tumbuh. Pola ini gagal dengan cara yang bisa diramalkan.

### Yang memberi rasa "dari nol" tanpa risikonya

**Package adalah slate kosong Anda.**

Kode baru lahir di `Packages/`, dengan aturan sendiri, tanpa satu pun utang dari
yang lama — karena package memang tidak bisa melihat isi App target. Itu
benar-benar mulai dari nol, hanya saja yang lama tetap rilis sementara yang baru
tumbuh.

App target menyusut pelan-pelan sampai tinggal komposisi. Tidak ada momen
"pindah semua sekaligus", dan tidak ada bulan tanpa rilis.

### Kalau tetap ingin membenahi file project-nya

Kerjakan sebagai pekerjaan tersendiri, terpisah dari kode:

1. Project baru, bundle ID sama.
2. Pakai **file system synchronized groups** (Xcode 15+) supaya folder di disk
   langsung jadi struktur project — ini menghilangkan sebagian besar konflik
   `pbxproj`.
3. Salin build setting **dengan sengaja**, satu per satu, bukan menyalin file
   lamanya.
4. Periksa satu per satu: entitlement, capability, app extension, konfigurasi
   Firebase, script CI, fastlane, code signing.

Nomor 4 yang paling sering luput, dan luputnya baru ketahuan di produksi —
push notification mati, deeplink mati, keychain sharing mati.

**Saran saya:** jangan lakukan bersamaan dengan pemecahan package. Satu
pekerjaan lebar pada satu waktu.

---

## 2. Root: splash → prelogin → main

### Masalah "hide and show"

Kalau ketiganya ada di pohon view bersamaan dengan visibilitas yang
di-*toggle*, ketiganya **hidup bersamaan**. Untuk aplikasi bank itu bukan
sekadar soal memori:

> Setelah logout, ViewModel dan data sesi sebelumnya masih ada di memori,
> karena view-nya cuma disembunyikan.

Itu temuan keamanan, bukan temuan performa.

### Bentuk yang disarankan

Satu fase, satu `switch`, tepat satu cabang yang hidup:

```swift
enum AppPhase {
    case splash
    case prelogin
    case main
}

final class AppPhaseStore: ObservableObject {
    @Published private(set) var phase: AppPhase = .splash

    func enterPrelogin() { phase = .prelogin }
    func enterMain()     { phase = .main }

    /// Logout: `.main` dirobohkan beserta seluruh isinya.
    func signOut()       { phase = .prelogin }
}
```

```swift
struct RootView: View {
    @ObservedObject var phaseStore: AppPhaseStore

    var body: some View {
        content
            .mountFlowRouter()          // di sini, di luar semuanya
    }

    @ViewBuilder private var content: some View {
        switch phaseStore.phase {
        case .splash:
            SplashScreen(viewModel: createSplashViewModel())

        case .prelogin:
            PreloginRootView()

        case .main:
            MainTabView(viewModel: createMainTabViewModel())
        }
    }
}
```

`switch` di `@ViewBuilder` membuat cabang yang tidak aktif **benar-benar tidak
ada** di pohon. Logout merobohkan `.main` beserta seluruh ViewModel di bawahnya,
dan itu terjadi karena bentuknya, bukan karena ada yang ingat membersihkan.

Pasang probe di satu ViewModel di dalam `.main`, lakukan logout, dan lihat
DEINIT-nya. Itu cara memastikannya dalam satu menit.

`.mountFlowRouter()` dipasang di `RootView`, di luar `switch` — supaya flow bisa
dibuka dari fase mana pun dan menutupi apa pun.

### `TabView` dengan lima tab

Jebakannya sama dengan yang sudah kita perbaiki di coordinator: **kalau setiap
tab membangun ViewModel-nya sebagai stored property, kelimanya dibangun
sekaligus** saat `MainTabView` di-init — termasuk empat yang belum pernah
dibuka, beserta semua permintaan jaringan yang menyertainya.

Karena iOS 13 tidak punya `@StateObject`, kepemilikannya ditaruh di satu objek:

```swift
final class MainTabViewModel: ObservableObject {
    @Published var selectedTab: MainTab = .dashboard

    private var dashboardViewModel: DashboardViewModel?
    private var financialViewModel: FinancialViewModel?

    /// Dibangun saat tab pertama kali dibuka, lalu dipakai lagi.
    func dashboard() -> DashboardViewModel {
        if let existing = dashboardViewModel {
            return existing
        }

        let viewModel = DashboardFactory().createViewModel(routing: …)
        dashboardViewModel = viewModel
        return viewModel
    }
}
```

Dua hal yang perlu diputuskan sadar, karena keduanya keputusan produk:

**Tab yang sudah dibuka tetap hidup.** Itu memang yang diinginkan — pindah tab
tidak boleh memuat ulang. Tetapi berarti memori tumbuh sampai lima tab, dan
berhenti di situ. Batasnya jelas, jadi bukan kebocoran.

**Apakah tab me-refresh saat dikunjungi lagi?** Kalau ya, itu `onAppear` yang
memicu `loadData()`, bukan membangun ulang ViewModel-nya. Bedakan keduanya —
membangun ulang berarti kehilangan posisi scroll dan state form.

---

## 3. Bottom sheet dan blocker

### Kenapa `ScreenContentViewModel` bukan tempatnya

Tiga alasan, dan yang ketiga menentukan.

**Setiap layar membawa mesinnya**, dipakai atau tidak. Layar yang tidak pernah
memunculkan sheet tetap menanggung `@Published`-nya.

**Invalidasi object-level.** `sheetState` berada di ViewModel yang sama dengan
seluruh isi layar, jadi membuka sheet meng-invalidasi seluruh layar — persoalan
yang sama dengan `scrollViewContentSize`.

**Blocker tidak bisa muncul di atas flow.** Ini yang paling menentukan sekarang.
Sesi habis, force update, atau maintenance harus tampil **di atas apa pun**,
termasuk di atas flow transfer yang dipresentasikan `.fullScreen`. Blocker yang
disimpan di ViewModel layar di bawahnya secara fisik tidak bisa menutupinya.

### Pisahkan dua hal yang selama ini satu

**Sheet milik layar** — pemilih rekening, pratinjau detail, konfirmasi lokal.
Tetap milik layar, tetapi di objek kecil tersendiri supaya tidak
meng-invalidasi seluruh layar:

```swift
final class SheetPresenter<Content>: ObservableObject {
    @Published var content: Content?
}
```

Yang mengamatinya cukup host sheet-nya, bukan seluruh layar.

**Blocker milik aplikasi** — sesi habis, force update, maintenance, koneksi
hilang. Satu presenter di tingkat aplikasi:

```swift
enum AppBlocker: Identifiable {
    case sessionExpired
    case forceUpdate(minimumVersion: String)
    case maintenance(message: String)

    var id: String { … }
}

final class BlockerPresenter: ObservableObject {
    static let shared = BlockerPresenter()

    @Published private(set) var current: AppBlocker?

    func show(_ blocker: AppBlocker) { current = blocker }
    func dismiss() { current = nil }
}
```

Dipanggil dari mana pun — interceptor jaringan, `UseCase`, `AppDelegate`:

```swift
BlockerPresenter.shared.show(.sessionExpired)
```

### Satu detail yang harus benar sejak awal

Karena flow dipresentasikan sebagai modal UIKit, **overlay SwiftUI di
`RootView` tidak akan menutupinya.** Presenter blocker harus mempresentasikan
dari view controller **paling atas**, bukan dari root:

```swift
private func topmostController() -> UIViewController? {
    var controller = UIApplication.shared
        .windows
        .first { $0.isKeyWindow }?
        .rootViewController

    while let presented = controller?.presentedViewController {
        controller = presented
    }

    return controller
}
```

Mekanismenya sama dengan `FlowPresenter`, hanya tujuannya berbeda: yang satu
membuka perjalanan, yang satu menutupi apa pun yang sedang tampil.

Kalau tidak ditangani begini, blocker akan tampak bekerja di layar biasa dan
**diam-diam tidak muncul** saat pengguna sedang di tengah transfer — persis saat
ia paling dibutuhkan.

---

## Urutan yang disarankan untuk ketiganya

1. **Root `switch`.** Paling murah, dan menutup satu persoalan keamanan.
   Terverifikasi dalam satu menit lewat probe saat logout.
2. **`MainTabViewModel` dengan pembangunan malas.** Menghilangkan empat ViewModel
   dan empat permintaan jaringan yang tidak pernah diminta.
3. **`BlockerPresenter` di tingkat aplikasi.** Kerjakan bersamaan dengan flow
   transfer, karena di situ kekurangannya baru terlihat.
4. **`SheetPresenter` per layar.** Belakangan, sambil menyentuh layarnya.

Keempatnya sempit — satu file, bisa dibatalkan sendiri. Tidak satu pun menuntut
pemecahan package lebih dulu.
