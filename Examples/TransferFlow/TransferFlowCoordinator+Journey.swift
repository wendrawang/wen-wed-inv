import SwiftUI

/// Percabangan setelah penerima dipilih.
///
/// Isinya **sama persis** dengan `startDestinationCoordinator`,
/// `startPrivateAccountJourney`, dan `startValasJourney` di
/// `TransferLandingCoordinator` — urutan `if`-nya, syaratnya, dan tujuannya
/// tidak diubah satu pun. Yang berganti hanya cara menyebut tujuannya: dari
/// menulis nama coordinator ke sebuah `String`, menjadi memanggil `start(_:)`
/// dengan sebuah rute.
///
/// Kesamaan itu disengaja. Percabangan ini aturan bisnis, bukan navigasi, dan
/// memindahkannya adalah kesempatan paling mudah untuk diam-diam mengubah
/// perilaku.
extension TransferFlowCoordinator {

    func createLandingScreen(
        transferCart: TransferCart,
        category: TransferCategory
    ) -> some View {
        TransferLandingFactory(
            transferCart: transferCart,
            predefineTransferCategory: category
        )
        .createScreen(routing: createLandingRouting())
    }

    /// `[weak self]` di kedua closure, dan ViewModel-nya **tidak** ditangkap —
    /// ia datang sebagai parameter. Keduanya wajib: closure ini berakhir
    /// tersimpan di `useCase.callback`, dan ViewModel menyimpan UseCase.
    private func createLandingRouting() -> TransferLandingFactory.Routing {
        TransferLandingFactory.Routing(
            onRequestNewRecipient: { [weak self] viewModel in
                self?.start(
                    .newRecipient(
                        useCase: viewModel.useCase,
                        category: viewModel.selectedTransferCategory
                    )
                )
            },
            onSubmissionSucceed: { [weak self] viewModel in
                self?.startAfterSubmission(viewModel.useCase)
            },
            // Landing adalah layar pertama tumpukan, jadi back di sini berarti
            // menutup flow dan kembali ke Dashboard.
            onRequestBack: { [weak self] _ in
                self?.goBackOrFinish()
            }
        )
    }
}

// MARK: - Percabangan

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

        start(.transactionAmount(useCase: useCase))
    }

    private func startPrivateAccountJourney(_ useCase: TransferLandingUseCase) {
        if useCase.repository.transferCart.targets.isEmpty {
            start(.debitAccountSelection(useCase: useCase))
            return
        }

        start(.transactionAmount(useCase: useCase))
    }

    private func startValasJourney(_ useCase: TransferLandingUseCase) {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            start(.currencySelection(useCase: useCase))
            return
        }

        if useCase.output.bank.code.isEmpty {
            start(.countrySelection(useCase: useCase))
            return
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            start(.telegraphicRecipientForm(useCase: useCase))
            return
        }

        start(.bankSummary(useCase: useCase))
    }
}
