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
    var onFinish: () -> Void = { return }

    private weak var navigationController: FlowNavigationController?

    init(navigationController: FlowNavigationController) {
        self.navigationController = navigationController
    }

    /// Menitipkan coordinator flow supaya umurnya mengikuti umur tumpukan.
    ///
    /// Dipanggil sekali oleh coordinator **teratas** saat ia dibuat. Tanpa ini,
    /// coordinator lepas begitu `createStack` selesai — seluruh layar hanya
    /// menyebutnya lewat `[weak self]`, jadi tidak ada satu pun yang memilikinya.
    ///
    /// ## Hanya satu, dan itu yang teratas
    ///
    /// Sebuah flow boleh punya beberapa coordinator — misalnya satu untuk
    /// cabang valas, memakai navigator yang sama. Tetapi hanya yang teratas
    /// yang menitipkan diri ke sini; coordinator anak dipegang **induknya**.
    ///
    /// Kalau anak ikut memanggil ini, ia menimpa titipan induknya, induknya
    /// lepas, dan seluruh perutean yang menyebut induk berhenti bekerja — diam,
    /// tanpa crash. Karena itu berisik di Debug.
    func retainForFlowLifetime(_ flowCoordinator: AnyObject) {
        if let existingCoordinator = navigationController?.flowCoordinator {
            assertionFailure(
                """
                \(type(of: existingCoordinator)) already owns this flow, so \
                \(type(of: flowCoordinator)) would replace it and silently \
                deallocate it. Only the top-level coordinator calls \
                retainForFlowLifetime; a child coordinator is held by its \
                parent instead.
                """
            )
            return
        }

        navigationController?.flowCoordinator = flowCoordinator
    }

    func push<Content: View>(
        _ content: Content,
        stepIdentifier: String? = nil,
        isAnimated: Bool = true
    ) {
        navigationController?.pushViewController(
            createController(for: content, stepIdentifier: stepIdentifier),
            animated: isAnimated
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
    func pushIsland<Content: View>(
        _ content: Content,
        stepIdentifier: String? = nil,
        isAnimated: Bool = true
    ) {
        navigationController?.pushViewController(
            createIslandController(for: content, stepIdentifier: stepIdentifier),
            animated: isAnimated
        )
    }

    /// Menyusun seluruh tumpukan sekaligus.
    ///
    /// Ini yang membuat "masuk ke tengah flow" mungkin: bukan dengan
    /// mendorong beberapa layar berturut-turut, tetapi dengan menyatakan
    /// tumpukan akhirnya. Coordinator yang menentukan tombol back-nya membawa ke
    /// mana — dengan menyertakan layar sebelumnya atau tidak.
    func setStack(_ controllers: [UIViewController], isAnimated: Bool = false) {
        navigationController?.setViewControllers(controllers, animated: isAnimated)
    }

    /// Membungkus satu layar menjadi controller, untuk disusun lewat `setStack`.
    func createController<Content: View>(
        for content: Content,
        stepIdentifier: String? = nil
    ) -> UIViewController {
        let controller = FlowStepHostingController(rootView: content)
        controller.stepIdentifier = stepIdentifier
        return controller
    }

    /// Versi pulau, untuk tumpukan awal yang ikut memuat rangkaian SwiftUI lama.
    ///
    /// Dengan ini `setStack` bisa mencampur keduanya bebas — misalnya
    /// `[landing, pulauLama, ringkasan]` — sehingga "masuk ke tengah" tetap
    /// mungkin walau sebagian langkahnya belum dipindah.
    func createIslandController<Content: View>(
        for content: Content,
        stepIdentifier: String? = nil
    ) -> UIViewController {
        let island = NavigationView {
            content
        }
        .navigationViewStyle(StackNavigationViewStyle())

        let controller = FlowIslandHostingController(rootView: island)
        controller.stepIdentifier = stepIdentifier
        return controller
    }

    /// Apakah layar teratas adalah layar pertama flow ini.
    ///
    /// Dipakai untuk memutuskan arti tombol back: di layar pertama, back berarti
    /// **menutup flow**, bukan mundur. Di `NavigationView` perbedaan ini tidak
    /// pernah muncul karena layar pertama flow tetap punya induk di tumpukan
    /// yang sama.
    var isAtRoot: Bool {
        (navigationController?.viewControllers.count ?? 0) <= 1
    }

    func pop(isAnimated: Bool = true) {
        navigationController?.popViewController(animated: isAnimated)
    }

    func popToRoot(isAnimated: Bool = true) {
        navigationController?.popToRootViewController(animated: isAnimated)
    }

    /// Mundur ke langkah yang **disebut namanya**.
    ///
    /// Inilah yang tidak punya padanan di `NavigationView`, dan yang selalu
    /// dibutuhkan flow transaksi: A → B → C → D, lalu dari D kembali ke B.
    ///
    /// Memakai nama, bukan hitungan mundur, karena hitungan mundur rapuh —
    /// begitu ada langkah bersyarat yang kadang masuk kadang tidak, angkanya
    /// salah, dan salahnya baru terlihat di tangan pengguna.
    ///
    /// Kalau ada dua layar dengan nama yang sama di tumpukan, yang dituju adalah
    /// yang **terdekat** dengan layar sekarang.
    @discardableResult
    func popTo(stepIdentifier: String, isAnimated: Bool = true) -> Bool {
        guard let controllers = navigationController?.viewControllers else {
            return false
        }

        let targetController = controllers.last { controller in
            (controller as? FlowStepHosting)?.stepIdentifier == stepIdentifier
        }

        guard let targetController = targetController else {
            assertionFailure(
                """
                No screen in the current stack is tagged "\(stepIdentifier)", \
                so this call does nothing. Push it with the same identifier \
                you pop back to.
                """
            )
            return false
        }

        navigationController?.popToViewController(
            targetController,
            animated: isAnimated
        )
        return true
    }

    /// Versi berbasis hitungan. Dipakai hanya kalau langkahnya tidak bernama.
    func popTo(stepsBack: Int, isAnimated: Bool = true) {
        guard let navigationController = navigationController else { return }

        let targetIndex = navigationController.viewControllers.count - 1 - stepsBack

        guard targetIndex >= 0 else {
            navigationController.popToRootViewController(animated: isAnimated)
            return
        }

        navigationController.popToViewController(
            navigationController.viewControllers[targetIndex],
            animated: isAnimated
        )
    }

    func finish() {
        onFinish()
    }
}
