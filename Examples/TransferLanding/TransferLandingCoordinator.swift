import SwiftUI

/// Coordinator versi perbaikan untuk Transfer Landing.
///
/// Mengikuti pola yang sama dengan `DetailDebitCardInfoCoordinator` — lihat
/// docs/SCREEN_PATTERN.md — dengan tiga tambahan yang khas layar panjang:
///
/// 1. Kamus sembilan closure diganti `switch`. Idenya tetap sama, hanya
///    tujuan yang cocok yang dibangun; yang hilang cuma alokasi kamus dan
///    sembilan konteks closure pada setiap evaluasi body.
/// 2. `.id(destinationCoordinatorName)` dihapus. Modifier itu membuat SwiftUI
///    merobohkan seluruh layar setiap kali tujuan berubah.
/// 3. Pembangunan tautan navigasi dipindah ke `NavigationLinkFactory`, sehingga
///    closure yang disimpan ViewModel hanya menangkap satu nilai kecil dengan
///    dependensi yang terlihat jelas — bukan salinan seluruh struct coordinator.
struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    @State private var destinationCoordinatorName: String?

    /// Tetap `var` dengan nilai default, persis seperti versi lama.
    ///
    /// Bentuk `var x = default` memberi parameter berdefault di memberwise
    /// init, sehingga pemanggil boleh tidak menyebutkannya. Menggantinya jadi
    /// `let x: T` tanpa default membuat parameternya **wajib** di setiap call
    /// site; menggantinya jadi `let x: T = default` malah menghapusnya sama
    /// sekali dari memberwise init, sehingga pemanggil yang memang mengisinya
    /// ikut gagal kompilasi.
    var predefineTransferCategory: TransferCategory = .unspecified

    var body: some View {
        LazyNavigationLink(
            tag: TransferLandingCoordinator.named,
            selection: $selectionCoordinatorName
        ) {
            createDestination()
        }
    }

    // MARK: - Pembangunan layar

    private func createDestination() -> some View {
        let useCase = createUseCase()
        let viewModel = createViewModel(useCase: useCase)

        return Screen {
            TransferLandingScreen(viewModel: viewModel)
        }
    }

    private func createUseCase() -> TransferLandingUseCase {
        let useCase = TransferLandingUseCase()
        let destination = $destinationCoordinatorName
        let cart = transferCart

        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory

        // `[weak useCase]` wajib di sini. Closure ini disimpan di
        // `useCase.callback`, jadi menangkapnya kuat berarti UseCase menahan
        // dirinya sendiri lewat callback-nya sendiri.
        useCase.callback.onSubmissionSucceed = { [weak useCase] in
            guard let useCase = useCase else { return }

            destination.wrappedValue = TransferLandingCoordinator.destinationName(
                for: useCase,
                transferCart: cart
            )
        }

        return useCase
    }

    private func createViewModel(
        useCase: TransferLandingUseCase
    ) -> TransferLandingViewModel {
        let viewModel = TransferLandingViewModel()
        let destination = $destinationCoordinatorName

        viewModel.navigationBarViewModel.title = navigationTitle()

        // Coordinator hanya menentukan tujuan. Kategori yang sedang terpilih
        // datang dari ViewModel sebagai argumen, bukan dibaca di sini.
        //
        // Versi lama membaca `viewModel.selectedTransferCategory` pada saat
        // ViewModel dibangun — yaitu sebelum `loadData()` pernah berjalan —
        // sehingga parameter analitiknya selalu berisi `.unspecified`.
        viewModel.onStartNewRecipient = { transferCategory in
            destination.wrappedValue = transferCategory
                .newRecipientDestinationCoordinatorName
        }

        viewModel.onCreateNavigationLinks = makeNavigationLinkFactory(
            useCase: useCase
        ).make

        viewModel.setUseCase(useCase)

        return viewModel
    }

    private func navigationTitle() -> String {
        guard !transferCart.targets.isEmpty else {
            return R.string.navigationTitle.transferRecipient.text
        }

        return String(
            format: R.string.navigationTitle.transferRecipientMultiple.text,
            transferCart.targets.count.nextNumber.ordinalText
        )
    }

    private func makeNavigationLinkFactory(
        useCase: TransferLandingUseCase
    ) -> NavigationLinkFactory {
        NavigationLinkFactory(
            selectionCoordinatorName: $selectionCoordinatorName,
            sourceCoordinatorName: $sourceCoordinatorName,
            destinationCoordinatorName: $destinationCoordinatorName,
            transferCart: $transferCart,
            useCase: useCase
        )
    }

    // MARK: - Perutean

    /// `static` supaya tidak menangkap struct coordinator saat dipakai di dalam
    /// closure `onSubmissionSucceed`.
    private static func destinationName(
        for useCase: TransferLandingUseCase,
        transferCart: TransferCart
    ) -> String {
        switch useCase.output.transferCategory {
        case .privateAccount:
            return transferCart.targets.isEmpty
                ? TransferDebitAccountSelectionCoordinator.named
                : TransferTransactionAmountCoordinator.named

        case .valas:
            return valasDestinationName(for: useCase)

        default:
            return TransferTransactionAmountCoordinator.named
        }
    }

    private static func valasDestinationName(
        for useCase: TransferLandingUseCase
    ) -> String {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            return TransferCurrencySelectionCoordinator.named
        }

        if useCase.output.bank.code.isEmpty {
            return TransferCountrySelectionCoordinator.named
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            return TelegraphicRecipientFormCoordinator.named
        }

        return BankSummaryCoordinator.named
    }
}
