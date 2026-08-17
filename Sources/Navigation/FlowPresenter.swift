import SwiftUI
import UIKit

/// Sambungan antara layar SwiftUI yang masih memakai `NavigationView` dengan
/// satu flow yang navigasinya UIKit.
///
/// **Ini satu-satunya titik temu keduanya**, dan itulah yang membuat migrasi
/// bisa dilakukan per flow. Dashboard tidak berubah sama sekali; ia hanya
/// menyalakan satu `Bool`. Layar di dalam flow tidak tahu-menahu soal
/// `NavigationView`.
///
/// Dipakai sebagai `.background(...)` supaya tidak menempati ruang:
///
/// ```swift
/// .background(
///     FlowPresenter(isPresented: $isTransferFlowPresented) { navigator in
///         TransferFlowCoordinator(
///             navigator: navigator,
///             transferCart: transferCart
///         ).start()
///     }
/// )
/// ```
///
/// Presentasinya `.fullScreen`, bukan sheet. Alasannya bukan selera: sheet di
/// iOS 13 bisa ditutup dengan swipe ke bawah kapan saja, dan flow transaksi
/// tidak boleh bisa ditinggalkan di tengah tanpa lewat jalur yang Anda kendalikan.
/// `.fullScreenCover` baru ada di iOS 14, jadi di iOS 13 presentasinya memang
/// harus lewat UIKit — dan itu justru yang kita lakukan di sini.
struct FlowPresenter<Root: View>: UIViewControllerRepresentable {

    @Binding var isPresented: Bool

    /// Membangun layar pertama flow. Dipanggil **sekali**, saat flow dibuka.
    let makeRoot: (FlowNavigator) -> Root

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
            [UIHostingController(rootView: makeRoot(navigator))],
            animated: false
        )

        context.coordinator.flowNavigationController = flowNavigationController
        host.present(flowNavigationController, animated: true)
    }

    private func dismissFlowIfNeeded(context: Context) {
        guard let flowNavigationController
            = context.coordinator.flowNavigationController else { return }

        context.coordinator.flowNavigationController = nil
        flowNavigationController.dismiss(animated: true)
    }
}
