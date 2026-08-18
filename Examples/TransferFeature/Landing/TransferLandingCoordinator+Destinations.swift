import SwiftUI

// MARK: - Tujuan

// PERUBAHAN: isi setiap entri kamus dipindah ke method sendiri, tanpa
// perubahan argumen. Yang berubah hanya tiga bentuk yang berulang:
//
//   $destinationCoordinatorName → destinationSelection(viewModel)
//   ekspresi ternary panjang     → childSourceCoordinatorName(viewModel)
//   $useCase.output.x            → useCase.binding(\.output.x)
//
// Ketiganya konsekuensi dari `useCase` dan penanda tujuan yang tidak lagi
// `@State` di coordinator.
extension TransferLandingCoordinator {

    private func createTransactionAmount(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        TransferTransactionAmountCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            recipientAccount: useCase.binding(\.output.recipientAccount),
            recipientProfile: .constant(TransactionActorProfile()),
            sourceAccount: $transferCart.sourceAccount,
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
            transferCategory: useCase.binding(\.output.transferCategory),
            predefineTransferPurpose: .constant(Option()),
            editTransferTarget: .constant(TransferTarget()),
            additionalInfo: useCase.binding(\.output.additionalInfo),
            transferMethods: useCase.binding(\.output.transferMethods),
            thematic: useCase.output.thematic
        )
    }

    private func createDebitAccountSelection(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        TransferDebitAccountSelectionCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            recipientAccount: useCase.binding(\.output.recipientAccount),
            recipientProfile: .constant(TransactionActorProfile()),
            transferCategory: useCase.binding(\.output.transferCategory),
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
            transferSpec: .constant(TransferSpec()),
            predefineTransferPurpose: .constant(Option()),
            backButtonAnalytic: .constant(
                AnalyticManager.instance.analytics.hitBackOnSourceAccountPrivateTransfer
            ),
            isUsingValidateValasCutOffTime: .constant(true),
            thematic: useCase.output.thematic
        )
    }

    private func createDomesticNewRecipient(
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        DomesticTransferNewRecipientCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart
        )
    }

    private func createForeignNewRecipient(
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        ForeignTransferNewRecipientCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart
        )
    }

    private func createProxyNewRecipient(
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        ProxyTransferNewRecipientCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart
        )
    }

    private func createCurrencySelection(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        TransferCurrencySelectionCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            recipientAccount: useCase.binding(\.output.recipientAccount),
            recipientProfile: .constant(TransactionActorProfile()),
            transferCategory: useCase.binding(\.output.transferCategory),
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
            predefineTransferPurpose: .constant(Option()),
            isUsingValidateValasCutOffTime: .constant(true),
            thematic: useCase.output.thematic
        )
    }

    private func createBankSummary(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        BankSummaryCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            bank: useCase.binding(\.output.bank),
            transferCategory: useCase.binding(\.output.transferCategory),
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod)
        )
    }

    private func createCountrySelection(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        TransferCountrySelectionCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            transferCategory: useCase.binding(\.output.transferCategory),
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod)
        )
    }

    private func createTelegraphicRecipientForm(
        _ useCase: TransferLandingUseCase,
        _ viewModel: TransferLandingViewModel
    ) -> some View {
        TelegraphicRecipientFormCoordinator(
            selectionCoordinatorName: destinationSelection(viewModel),
            sourceCoordinatorName: childSourceCoordinatorName(viewModel),
            transferCart: $transferCart,
            bank: useCase.binding(\.output.bank),
            transferCategory: useCase.binding(\.output.transferCategory),
            transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
            recipientAccount: useCase.binding(\.output.recipientAccount),
            additionalInfo: useCase.binding(\.output.additionalInfo)
        )
    }
}
