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

    // PERUBAHAN: method baru. Menggantikan `createViewModel()` yang dulu
    // dipanggil dari `body` pada setiap render.
    private func createDestination() -> some View {
        let useCase = createUseCase()
        let viewModel = createViewModel(useCase: useCase)

        // Dipasang di sini, bukan di `createUseCase()`, karena perutean menulis
        // penanda yang ada di ViewModel — jadi ViewModel harus sudah ada.
        useCase.callback.onSubmissionSucceed = { [weak useCase, weak viewModel] in
            guard let useCase = useCase, let viewModel = viewModel else { return }
            startDestinationCoordinator(for: useCase, on: viewModel)
        }

        return Screen {
            TransferLandingScreen(viewModel: viewModel)
        }
    }

    // PERUBAHAN: objek baru, bukan `@State` yang dipakai ulang.
    private func createUseCase() -> TransferLandingUseCase {
        let useCase = TransferLandingUseCase()

        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory

        return useCase
    }

    // PERUBAHAN: objek baru, dan cabang `if selectionCoordinatorName != named`
    // yang dulu mengembalikan ViewModel kosong dihapus — method ini sekarang
    // hanya berjalan sekali, jadi cabang itu tidak punya alasan lagi.
    private func createViewModel(
        useCase: TransferLandingUseCase
    ) -> TransferLandingViewModel {
        let viewModel = TransferLandingViewModel()

        // PERUBAHAN: `[weak viewModel, weak useCase]`. Closure ini disimpan di
        // ViewModel, jadi `useCase` yang ditangkap kuat berarti ViewModel
        // memegang UseCase lewat dua jalur — property dan closure ini. Satu
        // jalur weak sudah cukup: ViewModel-lah pemilik UseCase-nya, jadi
        // selama closure ini bisa dipanggil, UseCase-nya pasti masih ada.
        viewModel.onCreateNavigationLinks = { [weak viewModel, weak useCase] in
            guard let viewModel = viewModel, let useCase = useCase else {
                return DefaultValues.emptyAnyView
            }

            return createNavigationLinks(useCase: useCase, viewModel: viewModel)
        }

        viewModel.navigationBarViewModel.title = navigationTitle()

        viewModel.newRecipientMenuItemViewModel.analytic = AnalyticManager
            .instance
            .analytics
            .hitTransferLandingNewRecipient

        setupNewRecipientAction(on: viewModel)
        viewModel.setUseCase(useCase)

        return viewModel
    }

    private func navigationTitle() -> String {
        if transferCart.targets.isEmpty {
            return R.string.navigationTitle.transferRecipient.text
        }

        return String(
            format: R.string.navigationTitle.transferRecipientMultiple.text,
            transferCart.targets.count.nextNumber.ordinalText
        )
    }

    // PERUBAHAN: dulu `action = startNewRecipientCoordinator` dan
    // `analytic.parameters` diisi saat ViewModel dibangun. Keduanya membaca
    // `selectedTransferCategory`, dan itu hanya benar kalau pembangunannya
    // berulang setiap render. Sekarang sekali, jadi pembacaannya pindah ke
    // dalam aksinya.
    private func setupNewRecipientAction(on viewModel: TransferLandingViewModel) {
        viewModel.newRecipientMenuItemViewModel.action = { [weak viewModel] in
            guard let viewModel = viewModel else { return }

            viewModel.newRecipientMenuItemViewModel.analytic.parameters = [
                .categoryTitle: viewModel.selectedTransferCategory.rawValue
            ]

            startDestination(
                viewModel.selectedTransferCategory.newRecipientDestinationCoordinatorName,
                on: viewModel
            )
        }
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
