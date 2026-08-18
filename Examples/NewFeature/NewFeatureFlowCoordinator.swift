import SwiftUI
import UIKit

// =============================================================================
// TEMPLATE — SALIN FILE INI UNTUK FLOW BARU
//
// Cara pakai: salin, ganti seluruh kata "NewFeature" dengan nama fitur Anda,
// lalu isi kedua method pembangun layarnya.
//
// **Ini satu-satunya file yang wajib ada per flow.** Enum rute, struct factory,
// dan file `+Sesuatu` menyusul hanya kalau ada yang menuntutnya — lihat
// README.md di folder ini.
// =============================================================================

/// Coordinator untuk satu flow.
///
/// Tugasnya dua: menyusun tumpukan awal, dan memutuskan tujuan berikutnya.
/// Ia bukan `View`, jadi ia bisa melihat seluruh perjalanan sekaligus — itulah
/// yang membuat perutean bisa ditulis sebagai `if`/`else` biasa dan diuji tanpa
/// SwiftUI.
final class NewFeatureFlowCoordinator {

    private let navigator: FlowNavigator
    private let entryParameter: String

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    init(navigator: FlowNavigator, entryParameter: String) {
        self.navigator = navigator
        self.entryParameter = entryParameter

        // Wajib, dan hanya coordinator **teratas** yang memanggilnya. Seluruh
        // layar menyebut coordinator lewat `[weak self]`, jadi tanpa ini ia
        // lepas begitu `createStack()` selesai.
        navigator.retainForFlowLifetime(self)

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    /// Tumpukan awal. Untuk masuk dari depan, satu layar sudah cukup.
    func createStack() -> [UIViewController] {
        [navigator.createController(for: createFirstScreen())]
    }
}

// MARK: - Layar

extension NewFeatureFlowCoordinator {

    private func createFirstScreen() -> some View {
        let useCase = NewFeatureFirstUseCase()
        useCase.renewIdentifier()
        useCase.input.entryParameter = entryParameter

        let viewModel = NewFeatureFirstViewModel()

        // Layar pertama tumpukan: back berarti menutup flow, bukan mundur.
        viewModel.navigationBarViewModel.onTapBackButton = { [weak self] in
            self?.navigator.finish()
        }

        // `[weak self]` wajib — closure ini disimpan di UseCase, dan ViewModel
        // menyimpan UseCase.
        useCase.callback.onSubmissionSucceed = { [weak self, weak useCase] in
            guard let useCase = useCase else { return }

            self?.showSecondScreen(with: useCase.output.selectedValue)
        }

        viewModel.setUseCase(useCase)

        return Screen {
            NewFeatureFirstScreen(viewModel: viewModel)
        }
    }

    private func createSecondScreen(_ selectedValue: String) -> some View {
        let useCase = NewFeatureSecondUseCase()
        useCase.renewIdentifier()
        useCase.input.selectedValue = selectedValue

        let viewModel = NewFeatureSecondViewModel()

        // Layar tengah: back berarti mundur satu langkah.
        viewModel.navigationBarViewModel.onTapBackButton = { [weak self] in
            self?.navigator.pop()
        }

        useCase.callback.onSubmissionSucceed = { [weak self] in
            self?.navigator.finish()
        }

        viewModel.setUseCase(useCase)

        return Screen {
            NewFeatureSecondScreen(viewModel: viewModel)
        }
    }
}

// MARK: - Perpindahan

extension NewFeatureFlowCoordinator {

    /// Perutean adalah kode biasa. Kalau ada syarat, tulis `if` di sini —
    /// bukan di layar, dan bukan di dalam `body`.
    private func showSecondScreen(with selectedValue: String) {
        navigator.push(createSecondScreen(selectedValue))
    }
}

// MARK: - Pendaftaran ke router global

// Sepuluh baris ini yang membuat flow bisa dibuka dari mana pun:
//
//     AppRouter.shared.start(.newFeature(entryParameter: value))
//
// `AppRouter.swift` tidak perlu disentuh, sekarang maupun nanti.
extension PendingFlow {

    static func newFeature(entryParameter: String) -> PendingFlow {
        PendingFlow { navigator in
            NewFeatureFlowCoordinator(
                navigator: navigator,
                entryParameter: entryParameter
            )
            .createStack()
        }
    }
}
