import UIKit

/// `UINavigationController` untuk satu flow yang layarnya SwiftUI.
///
/// Dua penyesuaian, keduanya wajib kalau navigation bar-nya milik SwiftUI:
///
/// 1. Bar bawaan UIKit disembunyikan. Layar-layar Anda sudah menggambar bar
///    sendiri lewat `navigationBarViewModel`, jadi bar UIKit hanya akan menjadi
///    lapis kedua.
/// 2. Gestur swipe-back dikembalikan. Menyembunyikan bar mematikan gestur itu,
///    dan `delegate = nil` yang biasa disarankan orang membuat crash ketika
///    di-swipe di layar paling bawah.
///
/// ## Kenapa `override`, bukan `extension … : UIGestureRecognizerDelegate`
///
/// `UINavigationController` **sudah** conform ke `UIGestureRecognizerDelegate`
/// dan sudah punya implementasi `gestureRecognizerShouldBegin`. Menyatakan
/// konformansinya lagi berarti "Redundant conformance", dan menulis ulang
/// method-nya tanpa `override` berarti "Overriding declaration requires an
/// 'override' keyword".
///
/// Karena itu method-nya di-`override` **di dalam badan class** — Swift tidak
/// mengizinkan `override` di dalam extension.
final class FlowNavigationController: UINavigationController {

    /// Pemilik coordinator flow, dan satu-satunya referensi kuat kepadanya.
    ///
    /// Coordinator flow adalah class, dan seluruh layar hanya menyebutnya lewat
    /// `[weak self]` — jadi tanpa satu pemilik yang tegas, ia lepas begitu
    /// `createStack` selesai. Ditaruh di sini karena umurnya memang harus persis
    /// sama dengan umur tumpukannya: modal ditutup, controller ini dilepas,
    /// coordinator ikut lepas, dan seluruh ViewModel di dalamnya menyusul.
    ///
    /// Arah kepemilikannya sengaja satu arah dan tidak melingkar:
    /// controller → coordinator → navigator → (weak) controller.
    var flowCoordinator: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()

        isNavigationBarHidden = true

        // Delegate bawaannya objek internal UIKit yang mematikan gestur begitu
        // bar disembunyikan. Diambil alih supaya jawabannya kita yang tentukan.
        interactivePopGestureRecognizer?.delegate = self
    }

    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if viewControllers.count <= 1 {
            return false
        }

        guard let islandController = topViewController,
              islandController is FlowIslandHosting else {
            // Sengaja `true`, bukan `super`. Implementasi bawaannya justru
            // menolak saat bar disembunyikan, dan itu yang sedang kita perbaiki.
            return true
        }

        return isIslandAtItsRoot(islandController)
    }

    /// Apakah pulau SwiftUI di atas sedang menampilkan layar pertamanya.
    ///
    /// Kalau ya, gestur luar yang harus jalan — swipe berarti keluar dari pulau.
    /// Kalau pulaunya sudah mendorong layar sendiri, `NavigationView` di dalamnya
    /// yang menangani; dua gestur aktif bersamaan membuat satu swipe memundurkan
    /// dua tingkat sekaligus.
    ///
    /// **Best effort.** Ia bergantung pada `NavigationView` yang ditopang
    /// `UINavigationController` di dalam hierarki child. Kalau tidak ditemukan,
    /// jawabannya `false` — gestur luar dimatikan. Pilihan itu disengaja: swipe
    /// yang tidak bereaksi masih bisa diselamatkan tombol back, sedangkan mundur
    /// dua langkah tanpa disadari tidak.
    private func isIslandAtItsRoot(_ islandController: UIViewController) -> Bool {
        guard let innerNavigation = findNavigationController(
            in: islandController
        ) else {
            return false
        }

        return innerNavigation.viewControllers.count <= 1
    }

    private func findNavigationController(
        in controller: UIViewController
    ) -> UINavigationController? {
        for child in controller.children {
            if let navigation = child as? UINavigationController {
                return navigation
            }

            if let navigation = findNavigationController(in: child) {
                return navigation
            }
        }

        return nil
    }
}
