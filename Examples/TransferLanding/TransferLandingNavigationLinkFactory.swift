import SwiftUI

extension TransferLandingCoordinator {

    /// Membangun tautan navigasi untuk satu tujuan.
    ///
    /// Dipisahkan dari coordinator supaya `switch` sembilan cabangnya tidak
    /// berdesakan dengan logika perutean, dan supaya dependensinya terlihat
    /// jelas sebagai daftar property alih-alih tersebar di dalam kamus.
    ///
    /// Yang tidak berubah dari versi lama: hanya tujuan yang cocok dengan
    /// `destinationCoordinatorName` yang benar-benar dibangun. Itu sifat yang
    /// sudah benar sejak awal dan sengaja dipertahankan.
    struct NavigationLinkFactory {
        let selectionCoordinatorName: Binding<String?>
        let sourceCoordinatorName: Binding<String?>
        let destinationCoordinatorName: Binding<String?>
        let transferCart: Binding<TransferCart>
        let useCase: TransferLandingUseCase

        /// Tujuan kembali untuk seluruh coordinator anak.
        ///
        /// Versi lama menuliskan ekspresi ini sembilan kali, sekali di setiap
        /// entri kamus. Isinya identik, jadi cukup satu tempat.
        private var backTarget: Binding<String?> {
            guard sourceCoordinatorName.wrappedValue == nil else {
                return sourceCoordinatorName
            }

            return selectionCoordinatorName.didSet { _ in
                destinationCoordinatorName.wrappedValue = nil
            }
        }

        /// `switch`, bukan kamus.
        ///
        /// Versi lama memakai computed property berisi kamus sembilan closure,
        /// sehingga setiap akses — dan aksesnya terjadi di dalam `body` layar —
        /// mengalokasikan satu Dictionary beserta sembilan konteks closure,
        /// hanya untuk mengambil satu entri lalu membuang sisanya. `switch`
        /// tidak mengalokasikan apa pun dan tetap hanya membangun cabang yang
        /// cocok.
        func make() -> AnyView {
            guard let destination = destinationCoordinatorName.wrappedValue else {
                return DefaultValues.emptyAnyView
            }

            switch destination {
            case TransferTransactionAmountCoordinator.named:
                return AnyView(makeTransactionAmount())

            case TransferDebitAccountSelectionCoordinator.named:
                return AnyView(makeDebitAccountSelection())

            case DomesticTransferNewRecipientCoordinator.named:
                return AnyView(makeDomesticNewRecipient())

            case ForeignTransferNewRecipientCoordinator.named:
                return AnyView(makeForeignNewRecipient())

            case ProxyTransferNewRecipientCoordinator.named:
                return AnyView(makeProxyNewRecipient())

            case TransferCurrencySelectionCoordinator.named:
                return AnyView(makeCurrencySelection())

            case BankSummaryCoordinator.named:
                return AnyView(makeBankSummary())

            case TransferCountrySelectionCoordinator.named:
                return AnyView(makeCountrySelection())

            case TelegraphicRecipientFormCoordinator.named:
                return AnyView(makeTelegraphicRecipientForm())

            default:
                return DefaultValues.emptyAnyView
            }
        }

        // MARK: - Tujuan

        private func makeTransactionAmount() -> some View {
            TransferTransactionAmountCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                recipientAccount: output(\.output.recipientAccount),
                recipientProfile: .constant(TransactionActorProfile()),
                sourceAccount: transferCart.sourceAccount,
                transferMethod: output(\.output.predefineSelectedTransferMethod),
                transferCategory: output(\.output.transferCategory),
                predefineTransferPurpose: .constant(Option()),
                editTransferTarget: .constant(TransferTarget()),
                additionalInfo: output(\.output.additionalInfo),
                transferMethods: output(\.output.transferMethods),
                thematic: useCase.output.thematic
            )
        }

        private func makeDebitAccountSelection() -> some View {
            TransferDebitAccountSelectionCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                recipientAccount: output(\.output.recipientAccount),
                recipientProfile: .constant(TransactionActorProfile()),
                transferCategory: output(\.output.transferCategory),
                transferMethod: output(\.output.predefineSelectedTransferMethod),
                transferSpec: .constant(TransferSpec()),
                predefineTransferPurpose: .constant(Option()),
                backButtonAnalytic: .constant(
                    AnalyticManager
                        .instance
                        .analytics
                        .hitBackOnSourceAccountPrivateTransfer
                ),
                isUsingValidateValasCutOffTime: .constant(true),
                thematic: useCase.output.thematic
            )
        }

        private func makeDomesticNewRecipient() -> some View {
            DomesticTransferNewRecipientCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart
            )
        }

        private func makeForeignNewRecipient() -> some View {
            ForeignTransferNewRecipientCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart
            )
        }

        private func makeProxyNewRecipient() -> some View {
            ProxyTransferNewRecipientCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart
            )
        }

        private func makeCurrencySelection() -> some View {
            TransferCurrencySelectionCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                recipientAccount: output(\.output.recipientAccount),
                recipientProfile: .constant(TransactionActorProfile()),
                transferCategory: output(\.output.transferCategory),
                transferMethod: output(\.output.predefineSelectedTransferMethod),
                predefineTransferPurpose: .constant(Option()),
                isUsingValidateValasCutOffTime: .constant(true),
                thematic: useCase.output.thematic
            )
        }

        private func makeBankSummary() -> some View {
            BankSummaryCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                bank: output(\.output.bank),
                transferCategory: output(\.output.transferCategory),
                transferMethod: output(\.output.predefineSelectedTransferMethod)
            )
        }

        private func makeCountrySelection() -> some View {
            TransferCountrySelectionCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                transferCategory: output(\.output.transferCategory),
                transferMethod: output(\.output.predefineSelectedTransferMethod)
            )
        }

        private func makeTelegraphicRecipientForm() -> some View {
            TelegraphicRecipientFormCoordinator(
                selectionCoordinatorName: destinationCoordinatorName,
                sourceCoordinatorName: backTarget,
                transferCart: transferCart,
                bank: output(\.output.bank),
                transferCategory: output(\.output.transferCategory),
                transferMethod: output(\.output.predefineSelectedTransferMethod),
                recipientAccount: output(\.output.recipientAccount),
                additionalInfo: output(\.output.additionalInfo)
            )
        }

        // MARK: - Bantuan

        /// Membuat `Binding` ke sebuah field di `useCase.output`.
        ///
        /// Versi lama menulis `$useCase.output.recipientAccount`, yang hanya
        /// mungkin karena `useCase` disimpan sebagai `@State` di coordinator —
        /// dan itu berarti satu UseCase dialokasikan lalu dibuang pada setiap
        /// init struct. Di sini UseCase datang sebagai objek biasa, jadi
        /// binding-nya dibuat eksplisit.
        private func output<Value>(
            _ keyPath: ReferenceWritableKeyPath<TransferLandingUseCase, Value>
        ) -> Binding<Value> {
            Binding(
                get: { useCase[keyPath: keyPath] },
                set: { useCase[keyPath: keyPath] = $0 }
            )
        }
    }
}
