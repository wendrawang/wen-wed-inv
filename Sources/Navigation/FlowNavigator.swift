import SwiftUI
import UIKit

/// Navigasi satu flow, dipegang sebagai **objek biasa** — bukan view.
///
/// Ini inti dari perbedaannya dengan coordinator yang berbentuk `View`. Selama
/// coordinator adalah view, "ke mana selanjutnya" harus dinyatakan sebagai state
/// yang ikut dievaluasi setiap kali `body` jalan, dan tujuannya harus sudah
/// berdiri di pohon view sebelum dipakai. Semua kerumitan yang kita temui di
/// Transfer Landing lahir dari situ: `.id()` yang ternyata load-bearing,
/// penanda tujuan dua tahap, destination yang dibekukan, dan `AnyView` di
/// dalam `body` setiap layar.
///
/// Sebagai objek, "ke mana selanjutnya" cukup menjadi pemanggilan method. Layar
/// tujuan dibangun **pada saat** berpindah, bukan sebelumnya, sehingga tidak
/// ada yang perlu dibuat lazy — dan nilainya cukup dioper lewat inisialiser,
/// tidak perlu `Binding` yang menembus beberapa layar.
///
/// Umur objeknya juga menjadi deterministik: `pop` melepas
/// `UIHostingController`, yang melepas `rootView`, yang melepas ViewModel-nya.
/// Itulah yang membuat DEINIT muncul berpasangan di log.
final class FlowNavigator {

    /// Dipanggil saat flow-nya selesai. Diisi oleh yang mempresentasikan flow —
    /// lihat `FlowPresenter`. Sengaja tidak melakukan `dismiss` sendiri supaya
    /// arah datanya tetap satu arah: flow melapor selesai, yang
    /// mempresentasikan yang menutup.
    var onFinish: TypeAliasesVoidHandler = { return }

    private weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func push<Content: View>(_ content: Content, animated: Bool = true) {
        navigationController?.pushViewController(
            UIHostingController(rootView: content),
            animated: animated
        )
    }

    /// Mendorong sub-flow SwiftUI yang **masih memakai `NavigationView`**.
    ///
    /// Dipakai saat flow ini di tengah jalan perlu masuk ke rangkaian layar yang
    /// belum dipindah. Seluruh rangkaian itu menjadi **satu** entri di tumpukan
    /// UIKit — sebuah pulau. Di dalam pulau, navigasinya jalan seperti biasa
    /// dengan `NavigationLink`; keluar dari pulau berarti keluar seluruhnya.
    ///
    /// Karena itu pulau harus kecil. Kalau sebuah rangkaian perlu dimasuki
    /// kembali di tengah, ia bukan pulau — ia flow tersendiri.
    ///
    /// `StackNavigationViewStyle` dipasang supaya di iPad tidak berubah menjadi
    /// split view, dan `FlowIslandHostingController` menandai controller-nya
    /// supaya gestur swipe-back milik UIKit tidak bertabrakan dengan gestur
    /// milik `NavigationView` di dalamnya.
    func pushIsland<Content: View>(_ content: Content, animated: Bool = true) {
        let island = NavigationView {
            content
        }
        .navigationViewStyle(StackNavigationViewStyle())

        navigationController?.pushViewController(
            FlowIslandHostingController(rootView: island),
            animated: animated
        )
    }

    /// Menyusun seluruh tumpukan sekaligus.
    ///
    /// Ini yang membuat "masuk ke tengah flow" mungkin: bukan dengan
    /// mendorong beberapa layar berturut-turut, tetapi dengan menyatakan
    /// tumpukan akhirnya. Coordinator yang menentukan tombol back-nya membawa ke
    /// mana — dengan menyertakan layar sebelumnya atau tidak.
    func setStack(_ controllers: [UIViewController], animated: Bool = false) {
        navigationController?.setViewControllers(controllers, animated: animated)
    }

    /// Membungkus satu layar menjadi controller, untuk disusun lewat `setStack`.
    func controller<Content: View>(for content: Content) -> UIViewController {
        UIHostingController(rootView: content)
    }

    func pop(animated: Bool = true) {
        navigationController?.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        navigationController?.popToRootViewController(animated: animated)
    }

    /// Mundur ke layar tertentu di dalam flow ini.
    ///
    /// Inilah yang tidak punya padanan di `NavigationView`, dan yang selalu
    /// dibutuhkan flow transaksi: setelah konfirmasi berhasil, kembalinya bukan
    /// satu langkah dan bukan ke root, tetapi ke satu titik tertentu.
    func popTo(stepsBack: Int, animated: Bool = true) {
        guard let navigationController = navigationController else { return }

        let targetIndex = navigationController.viewControllers.count - 1 - stepsBack

        guard targetIndex >= 0 else {
            navigationController.popToRootViewController(animated: animated)
            return
        }

        navigationController.popToViewController(
            navigationController.viewControllers[targetIndex],
            animated: animated
        )
    }

    func finish() {
        onFinish()
    }
}

// Alias lokal supaya file ini tidak bergantung pada `TypeAliases` milik
// aplikasi. Saat disalin ke proyek, ganti dengan `TypeAliases.VoidHandler`.
typealias TypeAliasesVoidHandler = () -> Void
