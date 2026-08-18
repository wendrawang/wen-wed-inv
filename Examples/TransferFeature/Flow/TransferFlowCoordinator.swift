import SwiftUI
import UIKit

/// Coordinator flow transfer — **satu file, seperti flow lainnya.**
///
/// Bentuknya sama persis dengan template di `Examples/NewFeature/`: class
/// coordinator, layar sebagai method privat, dan pendaftaran `PendingFlow` di
/// bagian bawah.
///
/// Tugasnya dua: menyusun tumpukan awal, dan memutuskan tujuan berikutnya.
final class TransferFlowCoordinator {

    /// Nama langkah, untuk `goBack(to:)`. Konstanta, bukan string berserakan.
    enum Step: String {
        case landing
        case newRecipient
        case transactionAmount
        case debitAccountSelection
        case currencySelection
        case countrySelection
        case telegraphicRecipientForm
        case bankSummary
    }

    private let navigator: FlowNavigator
    private let transferCart: TransferCart
    private let predefineTransferCategory: TransferCategory

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    init(
        navigator: FlowNavigator,
        transferCart: TransferCart,
        predefineTransferCategory: TransferCategory = .unspecified
    ) {
        self.navigator = navigator
        self.transferCart = transferCart
        self.predefineTransferCategory = predefineTransferCategory

        // Wajib. Seluruh layar menyebut coordinator lewat `[weak self]`, jadi
        // tanpa ini ia lepas begitu `createStack()` selesai.
        navigator.retainForFlowLifetime(self)

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    func createStack() -> [UIViewController] {
        [
            navigator.createController(
                for: createLandingScreen(),
                stepIdentifier: Step.landing.rawValue
            )
        ]
    }

    /// Mundur ke langkah bernama — misalnya dari ringkasan kembali ke nominal.
    func goBack(to step: Step) {
        navigator.popTo(stepIdentifier: step.rawValue)
    }
}

// MARK: - Layar pertama

extension TransferFlowCoordinator {

    /// Memakai `TransferLandingFactory` karena layar ini punya **dua**
    /// pemanggil: flow ini dan `TransferLandingCoordinator` lama yang masih
    /// melayani jalur `NavigationView`. Layar yang hanya punya satu pemanggil
    /// tidak perlu factory — bangun langsung di sini seperti contoh template.
    private func createLandingScreen() -> some View {
        TransferLandingFactory(
            transferCart: transferCart,
            predefineTransferCategory: predefineTransferCategory
        )
        .createScreen(routing: createLandingRouting())
    }

    /// `[weak self]` di ketiganya, dan ViewModel-nya **tidak** ditangkap —
    /// ia datang sebagai parameter. Closure ini berakhir tersimpan di
    /// `useCase.callback`, dan ViewModel menyimpan UseCase.
    private func createLandingRouting() -> TransferLandingFactory.Routing {
        TransferLandingFactory.Routing(
            onRequestNewRecipient: { [weak self] viewModel in
                self?.showNewRecipient(
                    viewModel.useCase,
                    category: viewModel.selectedTransferCategory
                )
            },
            onSubmissionSucceed: { [weak self] viewModel in
                self?.startAfterSubmission(viewModel.useCase)
            },
            // Landing adalah layar pertama tumpukan, jadi back menutup flow.
            onRequestBack: { [weak self] _ in
                self?.navigator.finish()
            }
        )
    }
}

// MARK: - Percabangan setelah penerima dipilih

// Isinya **sama persis** dengan `startDestinationCoordinator`,
// `startPrivateAccountJourney`, dan `startValasJourney` di
// `TransferLandingCoordinator` — urutan `if`-nya, syaratnya, dan tujuannya tidak
// diubah satu pun. Yang berganti hanya cara menyebut tujuannya.
extension TransferFlowCoordinator {

    private func startAfterSubmission(_ useCase: TransferLandingUseCase) {
        if useCase.output.transferCategory == .privateAccount {
            startPrivateAccountJourney(useCase)
            return
        }

        if useCase.output.transferCategory == .valas {
            startValasJourney(useCase)
            return
        }

        showTransactionAmount(useCase)
    }

    private func startPrivateAccountJourney(_ useCase: TransferLandingUseCase) {
        if useCase.repository.transferCart.targets.isEmpty {
            showDebitAccountSelection(useCase)
            return
        }

        showTransactionAmount(useCase)
    }

    private func startValasJourney(_ useCase: TransferLandingUseCase) {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            showCurrencySelection(useCase)
            return
        }

        if useCase.output.bank.code.isEmpty {
            showCountrySelection(useCase)
            return
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            showTelegraphicRecipientForm(useCase)
            return
        }

        showBankSummary(useCase)
    }
}

// MARK: - Tujuan — yang perlu Anda isi

// Tujuh method di bawah ini sengaja kosong. Isi satu per satu, mengikuti satu
// jalur transaksi sampai selesai — jalur IDR ke penerima tersimpan hanya
// melewati `showTransactionAmount`.
//
// Bentuk isiannya sama dengan `createLandingScreen()`: bangun UseCase, isi
// `input`-nya dari `useCase.output`, bangun ViewModel, pasang aksi back-nya ke
// `navigator.pop()`, lalu kembalikan `Screen { … }`.
extension TransferFlowCoordinator {

    private func showNewRecipient(
        _ useCase: TransferLandingUseCase,
        category: TransferCategory
    ) {
        navigator.push(EmptyView(), stepIdentifier: Step.newRecipient.rawValue)
    }

    private func showTransactionAmount(_ useCase: TransferLandingUseCase) {
        navigator.push(
            EmptyView(),
            stepIdentifier: Step.transactionAmount.rawValue
        )
    }

    private func showDebitAccountSelection(_ useCase: TransferLandingUseCase) {
        navigator.push(
            EmptyView(),
            stepIdentifier: Step.debitAccountSelection.rawValue
        )
    }

    private func showCurrencySelection(_ useCase: TransferLandingUseCase) {
        navigator.push(
            EmptyView(),
            stepIdentifier: Step.currencySelection.rawValue
        )
    }

    private func showCountrySelection(_ useCase: TransferLandingUseCase) {
        navigator.push(
            EmptyView(),
            stepIdentifier: Step.countrySelection.rawValue
        )
    }

    private func showTelegraphicRecipientForm(_ useCase: TransferLandingUseCase) {
        navigator.push(
            EmptyView(),
            stepIdentifier: Step.telegraphicRecipientForm.rawValue
        )
    }

    private func showBankSummary(_ useCase: TransferLandingUseCase) {
        navigator.push(EmptyView(), stepIdentifier: Step.bankSummary.rawValue)
    }
}

// MARK: - Pendaftaran ke router global

extension PendingFlow {

    /// ```swift
    /// AppRouter.shared.start(.transfer(transferCart: TransferCart()))
    /// ```
    static func transfer(
        transferCart: TransferCart,
        predefineTransferCategory: TransferCategory = .unspecified
    ) -> PendingFlow {
        PendingFlow { navigator in
            TransferFlowCoordinator(
                navigator: navigator,
                transferCart: transferCart,
                predefineTransferCategory: predefineTransferCategory
            )
            .createStack()
        }
    }
}
