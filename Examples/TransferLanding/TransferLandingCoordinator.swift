import SwiftUI

// =============================================================================
// CATATAN NAVIGASI
//
// `LazyNavigationLink` membangun destination sekali lalu membekukan hasilnya.
// Layar yang ter-push hanya mengamati `viewModel` — ia tidak mengamati `@State`
// milik coordinator sama sekali. Karena itu penanda tujuan disimpan di
// ViewModel, bukan di sini; kalau disimpan di sini, menulisnya hanya
// meng-invalidasi body coordinator dan `renderNavigationLinks()` di layar tidak
// pernah dievaluasi ulang.
//
// Tujuannya juga disimpan dalam **dua tahap**, karena `NavigationView` iOS
// 13–14 tidak melakukan push untuk tautan yang disisipkan dalam keadaan sudah
// terpilih. Penanda pertama menentukan tautan mana yang dibangun; penanda kedua
// menyalakan selection-nya satu putaran runloop kemudian.
//
// Kalau navigasinya masih bermasalah, yang perlu dikembalikan hanya tiga hal:
// `LazyNavigationLink` menjadi `NavigationLink` biasa, `.id()` dipasang lagi,
// dan `useCase`/`viewModel` kembali menjadi `@State`. Seluruh perbaikan di
// ViewModel dan UseCase tidak terkait navigasi dan tetap berlaku.
// =============================================================================

struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    // PERUBAHAN: `@State useCase`, `private let viewModel`, dan
    // `@State destinationCoordinatorName` dihapus. Dua yang pertama dibangun di
    // `createDestination()`; yang ketiga pindah ke ViewModel.

    var predefineTransferCategory: TransferCategory = .unspecified

    // PERUBAHAN: `NavigationLink` + `.id()` menjadi `LazyNavigationLink`.
    var body: some View {
        LazyNavigationLink(
            tag: TransferLandingCoordinator.named,
            selection: $selectionCoordinatorName
        ) {
            createDestination()
        }
    }
}

// MARK: - Pembangunan layar

extension TransferLandingCoordinator {

    // PERUBAHAN: seluruh pembangunan pindah ke `TransferLandingFactory`.
    //
    // Yang tersisa di coordinator hanya dua hal, dan keduanya memang urusan
    // navigasi: perutean lewat `Routing`, dan `onCreateNavigationLinks` yang
    // hanya ada di dunia `NavigationView`.
    //
    // `createUseCase()`, `createViewModel(useCase:)`, `navigationTitle()`, dan
    // `setupNewRecipientAction(on:)` dihapus dari file ini — isinya sama persis,
    // sekarang ada di factory.
    private func createDestination() -> some View {
        let viewModel = TransferLandingFactory(
            transferCart: transferCart,
            predefineTransferCategory: predefineTransferCategory
        )
        .makeViewModel(routing: destinationRouting())

        // Tetap di sini: `AnyView` tujuan tidak punya padanan di dunia UIKit,
        // jadi ia bukan milik factory. Layar yang dibangun coordinator flow
        // cukup tidak mengisinya.
        viewModel.onCreateNavigationLinks = { [weak viewModel] in
            guard let viewModel = viewModel else {
                return DefaultValues.emptyAnyView
            }

            return createNavigationLinks(
                useCase: viewModel.useCase,
                viewModel: viewModel
            )
        }

        return Screen {
            TransferLandingScreen(viewModel: viewModel)
        }
    }

    // PERUBAHAN: method baru. Dua keputusan tujuan yang dulu tersebar di
    // `createViewModel` dan `createDestination`, sekarang berdampingan.
    //
    // ViewModel-nya datang sebagai parameter, tidak ditangkap — closure ini
    // berakhir tersimpan di `useCase.callback`, dan ViewModel menyimpan UseCase.
    private func destinationRouting() -> TransferLandingFactory.Routing {
        TransferLandingFactory.Routing(
            onRequestNewRecipient: { viewModel in
                startDestination(
                    viewModel.selectedTransferCategory.newRecipientDestinationCoordinatorName,
                    on: viewModel
                )
            },
            onSubmissionSucceed: { viewModel in
                startDestinationCoordinator(
                    for: viewModel.useCase,
                    on: viewModel
                )
            }
        )
    }
}

// MARK: - Perpindahan tujuan

extension TransferLandingCoordinator {

    // PERUBAHAN: menggantikan penulisan langsung ke `destinationCoordinatorName`.
    // Keputusannya sama; yang berubah ke mana hasilnya ditulis, dan bahwa
    // penyalaannya dua tahap.
    private func startDestination(
        _ coordinatorName: String,
        on viewModel: TransferLandingViewModel
    ) {
        // Tahap 1 — tautannya masuk ke pohon, belum terpilih.
        viewModel.pendingDestinationCoordinatorName = coordinatorName

        // Tahap 2 — selection-nya dinyalakan setelah SwiftUI selesai
        // menyisipkan tautannya.
        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.activeDestinationCoordinatorName = coordinatorName
        }
    }

    private func startDestinationCoordinator(
        for useCase: TransferLandingUseCase,
        on viewModel: TransferLandingViewModel
    ) {
        if useCase.output.transferCategory == .privateAccount {
            startPrivateAccountJourney(on: viewModel)
            return
        }

        if useCase.output.transferCategory == .valas {
            startValasJourney(for: useCase, on: viewModel)
            return
        }

        startDestination(TransferTransactionAmountCoordinator.named, on: viewModel)
    }

    private func startPrivateAccountJourney(on viewModel: TransferLandingViewModel) {
        if transferCart.targets.isEmpty {
            startDestination(
                TransferDebitAccountSelectionCoordinator.named,
                on: viewModel
            )
            return
        }

        startDestination(TransferTransactionAmountCoordinator.named, on: viewModel)
    }

    private func startValasJourney(
        for useCase: TransferLandingUseCase,
        on viewModel: TransferLandingViewModel
    ) {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            startDestination(TransferCurrencySelectionCoordinator.named, on: viewModel)
            return
        }

        if useCase.output.bank.code.isEmpty {
            startDestination(TransferCountrySelectionCoordinator.named, on: viewModel)
            return
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            startDestination(TelegraphicRecipientFormCoordinator.named, on: viewModel)
            return
        }

        startDestination(BankSummaryCoordinator.named, on: viewModel)
    }
}

// MARK: - Tautan navigasi

// PERUBAHAN: kamus `navigationLinks` diganti `switch` dengan satu method kecil
// per tujuan.
//
// Kamusnya dulu terpaksa: satu-satunya alternatif adalah membangun semua anak
// sekaligus, dan itu yang membuat layar ini berat. `switch` memberi sifat lazy
// yang sama — hanya cabang yang cocok yang dibangun — tanpa dua kerugian
// kamusnya: tidak ada Dictionary beserta sembilan konteks closure yang
// dialokasikan pada setiap evaluasi body, dan tidak ada satu method raksasa
// yang melanggar batas panjang.
extension TransferLandingCoordinator {

    private func createNavigationLinks(
        useCase: TransferLandingUseCase,
        viewModel: TransferLandingViewModel
    ) -> AnyView {
        guard let destination = viewModel.pendingDestinationCoordinatorName else {
            return DefaultValues.emptyAnyView
        }

        return navigationLink(
            for: destination,
            useCase: useCase,
            viewModel: viewModel
        )
    }

    private func navigationLink(
        for destination: String,
        useCase: TransferLandingUseCase,
        viewModel: TransferLandingViewModel
    ) -> AnyView {
        switch destination {
        case TransferTransactionAmountCoordinator.named:
            return AnyView(createTransactionAmount(useCase, viewModel))

        case TransferDebitAccountSelectionCoordinator.named:
            return AnyView(createDebitAccountSelection(useCase, viewModel))

        case DomesticTransferNewRecipientCoordinator.named:
            return AnyView(createDomesticNewRecipient(viewModel))

        case ForeignTransferNewRecipientCoordinator.named:
            return AnyView(createForeignNewRecipient(viewModel))

        case ProxyTransferNewRecipientCoordinator.named:
            return AnyView(createProxyNewRecipient(viewModel))

        case TransferCurrencySelectionCoordinator.named:
            return AnyView(createCurrencySelection(useCase, viewModel))

        case BankSummaryCoordinator.named:
            return AnyView(createBankSummary(useCase, viewModel))

        case TransferCountrySelectionCoordinator.named:
            return AnyView(createCountrySelection(useCase, viewModel))

        case TelegraphicRecipientFormCoordinator.named:
            return AnyView(createTelegraphicRecipientForm(useCase, viewModel))

        default:
            return DefaultValues.emptyAnyView
        }
    }

    private func destinationSelection(
        _ viewModel: TransferLandingViewModel
    ) -> Binding<String?> {
        viewModel.binding(\.activeDestinationCoordinatorName)
    }

    // PERUBAHAN: ekspresi ini dulu ditulis sembilan kali dengan isi identik.
    // Namanya menyebut posisinya — nilai yang dioper ke parameter
    // `sourceCoordinatorName` milik anak — bukan kegunaannya, karena apa yang
    // dilakukan setiap anak dengan nilai itu berbeda-beda.
    //
    // Badan `didSet`-nya kini membersihkan kedua penanda.
    private func childSourceCoordinatorName(
        _ viewModel: TransferLandingViewModel
    ) -> Binding<String?> {
        if sourceCoordinatorName != nil {
            return $sourceCoordinatorName
        }

        return $selectionCoordinatorName.didSet { [weak viewModel] _ in
            viewModel?.activeDestinationCoordinatorName = nil
            viewModel?.pendingDestinationCoordinatorName = nil
        }
    }
}

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
