import SwiftUI
import UIKit

/// Sambungan antara layar SwiftUI yang masih memakai `NavigationView` dengan
/// satu flow yang navigasinya UIKit.
///
/// **Ini satu-satunya titik temu keduanya**, dan itulah yang membuat migrasi
/// bisa dilakukan per flow. Dashboard tidak berubah bentuk; ia hanya menyalakan
/// satu `Bool`. Layar di dalam flow tidak tahu-menahu soal `NavigationView`.
///
/// Biasanya tidak dipakai langsung — `AppRouter` yang memakainya, lewat
/// `.mountFlowRouter()`. Dipasang sebagai `.background(...)` supaya tidak
/// menempati ruang.
///
/// `createStack` mengembalikan **seluruh tumpukan**, bukan hanya layar pertama.
/// Itu yang membuat "masuk ke tengah flow" menjadi kemampuan biasa, bukan
/// tambalan: coordinator menyusun `[landing, amount]` kalau tombol back harus
/// membawa ke landing, atau `[amount]` saja kalau back harus keluar dari flow.
/// `NavigationView` tidak punya padanan untuk ini.
///
/// Presentasinya `.fullScreen` lewat UIKit. `.fullScreenCover` baru ada di
/// iOS 14, dan sheet iOS 13 bisa ditutup dengan swipe kapan saja — flow
/// transaksi tidak boleh bisa ditinggalkan di tengah lewat jalur yang tidak
/// Anda kendalikan.
struct FlowPresenter: UIViewControllerRepresentable {

    @Binding var isPresented: Bool

    /// Menyusun tumpukan awal flow. Dipanggil **sekali**, saat flow dibuka.
    let createStack: (FlowNavigator) -> [UIViewController]

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        if isPresented {
            presentFlowIfNeeded(from: uiViewController, context: context)
            return
        }

        dismissFlowIfNeeded(context: context)
    }

    func makeCoordinator() -> PresentationState {
        PresentationState()
    }

    /// Menyimpan navigation controller yang sedang tampil, supaya
    /// `updateUIViewController` bisa membedakan "belum tampil" dari "sudah".
    final class PresentationState {
        var flowNavigationController: FlowNavigationController?
    }
}

// MARK: - Presentasi

extension FlowPresenter {

    private func presentFlowIfNeeded(
        from host: UIViewController,
        context: Context
    ) {
        guard context.coordinator.flowNavigationController == nil else { return }

        // Saat `updateUIViewController` pertama kali dipanggil, host bisa jadi
        // belum menempel ke window — dan `present` dari controller yang belum
        // menempel tidak menghasilkan apa-apa. Ditunda satu putaran runloop.
        guard host.view.window != nil else {
            DispatchQueue.main.async {
                presentFlowIfNeeded(from: host, context: context)
            }
            return
        }

        let flowNavigationController = createFlowNavigationController()

        context.coordinator.flowNavigationController = flowNavigationController
        host.present(flowNavigationController, animated: true)
    }

    private func createFlowNavigationController() -> FlowNavigationController {
        let flowNavigationController = FlowNavigationController()
        flowNavigationController.modalPresentationStyle = .fullScreen

        let navigator = FlowNavigator(
            navigationController: flowNavigationController
        )

        // Flow melapor selesai; penutupannya lewat `isPresented`, bukan
        // `dismiss` langsung, supaya SwiftUI dan UIKit tidak punya dua versi
        // kebenaran tentang apakah flow-nya sedang tampil.
        navigator.onFinish = {
            isPresented = false
        }

        flowNavigationController.setViewControllers(
            createStack(navigator),
            animated: false
        )

        return flowNavigationController
    }

    private func dismissFlowIfNeeded(context: Context) {
        guard let flowNavigationController
            = context.coordinator.flowNavigationController else { return }

        context.coordinator.flowNavigationController = nil
        flowNavigationController.dismiss(animated: true)
    }
}
