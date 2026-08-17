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
///    di-swipe di layar paling bawah. Delegate di bawah menolak gesturnya saat
///    tumpukan hanya berisi satu layar.
final class FlowNavigationController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()

        isNavigationBarHidden = true
        interactivePopGestureRecognizer?.delegate = self
    }
}

extension FlowNavigationController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        viewControllers.count > 1
    }
}
