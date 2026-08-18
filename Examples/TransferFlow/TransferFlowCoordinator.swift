import SwiftUI
import UIKit

/// Coordinator flow transfer — class biasa, bukan `View`.
///
/// Tugasnya dua, dan hanya dua: menyusun tumpukan awal, dan memutuskan tujuan
/// berikutnya. Ia tidak tahu cara membangun satu pun layar tujuan (itu
/// `TransferScreenFactories`) dan tidak tahu cara mendorongnya (itu
/// `FlowNavigator`).
///
/// ## Umur objek
///
/// Dititipkan ke `FlowNavigationController` lewat `retainForFlowLifetime`,
/// karena seluruh layar hanya menyebutnya lewat `[weak self]` — tanpa satu
/// pemilik yang tegas ia lepas begitu `createStack` selesai. Rantainya satu
/// arah: controller → coordinator → navigator → (weak) controller. Modal
/// ditutup, semuanya ikut lepas.
final class TransferFlowCoordinator {

    let navigator: FlowNavigator
    let screenFactories: TransferScreenFactories

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    init(
        navigator: FlowNavigator,
        screenFactories: TransferScreenFactories
    ) {
        self.navigator = navigator
        self.screenFactories = screenFactories

        navigator.retainForFlowLifetime(self)

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }
}

// MARK: - Tumpukan awal

extension TransferFlowCoordinator {

    /// Menyusun **seluruh** tumpukan awal, bukan hanya layar pertama.
    ///
    /// Masuk lewat landing menghasilkan satu layar. Masuk ke tengah — dari
    /// deeplink, notifikasi, atau layar SwiftUI mana pun — menghasilkan landing
    /// di bawah dan tujuannya di atas, supaya tombol back tetap masuk akal.
    ///
    /// Landing yang di bawah tidak langsung memuat data: `loadData()` dipicu
    /// `onAppear`, dan layar yang tidak pernah tampil tidak memicunya. Itu perlu
    /// dipastikan sekali di aplikasi — kalau ternyata `setViewControllers` ikut
    /// memuat view-nya, ganti menjadi tumpukan satu layar untuk rute non-landing.
    func createStack(enteringAt route: TransferRoute) -> [UIViewController] {
        if case .landing(let transferCart, let category) = route {
            return [
                navigator.createController(
                    for: createLandingScreen(
                        transferCart: transferCart,
                        category: category
                    )
                )
            ]
        }

        return createMidFlowStack(for: route)
    }

    private func createMidFlowStack(
        for route: TransferRoute
    ) -> [UIViewController] {
        guard let destinationScreen = screenFactories.createScreen(for: route),
              let landingUseCase = route.landingUseCase else {
            return []
        }

        let landingScreen = createLandingScreen(
            transferCart: landingUseCase.repository.transferCart,
            category: landingUseCase.repository.transferCategory
        )

        return [
            navigator.createController(for: landingScreen),
            navigator.createController(for: destinationScreen)
        ]
    }
}

// MARK: - TransferRouting

extension TransferFlowCoordinator: TransferRouting {

    func start(_ route: TransferRoute) {
        navigator.push(createScreen(for: route))
    }

    func goBack() {
        navigator.pop()
    }

    func goBackToLanding() {
        navigator.popToRoot()
    }

    func finishFlow() {
        navigator.finish()
    }

    /// Landing dibangun sendiri di sini karena ia satu-satunya layar yang
    /// factory-nya sudah dimiliki flow ini. Sisanya milik aplikasi.
    private func createScreen(for route: TransferRoute) -> AnyView {
        if case .landing(let transferCart, let category) = route {
            return AnyView(
                createLandingScreen(
                    transferCart: transferCart,
                    category: category
                )
            )
        }

        guard let screen = screenFactories.createScreen(for: route) else {
            assertionFailure(
                """
                No screen factory is registered for \(route). Every case of \
                TransferRoute except .landing must be supplied through \
                TransferScreenFactories where the flow is mounted.
                """
            )
            return DefaultValues.emptyAnyView
        }

        return screen
    }
}

// MARK: - Rute

extension TransferRoute {

    /// UseCase landing yang dibawa rute ini, kalau ada.
    ///
    /// Dipakai saat masuk ke tengah flow: dari sinilah keranjang dan kategori
    /// untuk layar landing di bawahnya dibaca.
    var landingUseCase: TransferLandingUseCase? {
        switch self {
        case .landing:
            return nil

        case .newRecipient(let useCase, _):
            return useCase

        case .transactionAmount(let useCase),
             .debitAccountSelection(let useCase),
             .currencySelection(let useCase),
             .countrySelection(let useCase),
             .telegraphicRecipientForm(let useCase),
             .bankSummary(let useCase):
            return useCase
        }
    }
}
