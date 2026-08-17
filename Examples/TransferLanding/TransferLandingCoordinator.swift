import SwiftUI

// =============================================================================
// PENYEBAB NAVIGASI TIDAK JALAN DI PERCOBAAN SEBELUMNYA
//
// Bukan soal NavigationView, tapi soal dependency tracking SwiftUI.
//
// `LazyNavigationLink` membangun destination sekali lalu membekukan hasilnya.
// Layar yang ter-push hanya mengamati `viewModel` (ObservableObject) — ia tidak
// mengamati `@State` milik coordinator sama sekali.
//
// Jadi saat `startDestination()` menulis `@State` di coordinator, yang
// di-invalidasi hanyalah body coordinator — dan body itu cuma membangun ulang
// `LazyNavigationLink`, yang langsung memakai destination dari cache.
// `renderNavigationLinks()` di layar **tidak pernah** dievaluasi ulang,
// sehingga tautan anak tidak pernah muncul di pohon view.
//
// Versi lama tidak terkena karena destination-nya tidak lazy: body coordinator
// yang dievaluasi ulang ikut membangun ulang seluruh `Screen`, dan `.id()`
// memaksa subtree-nya diganti.
//
// PERBAIKANNYA: state tujuan dipindah ke ViewModel. Layar mengamati ViewModel,
// jadi menulisnya benar-benar memicu evaluasi ulang di layar yang ter-push.
//
// Kalau ini masih belum jalan, yang perlu dikembalikan hanya tiga hal —
// `LazyNavigationLink` menjadi `NavigationLink` biasa, `.id()` dipasang lagi,
// dan `useCase`/`viewModel` kembali menjadi `@State` di coordinator. Seluruh
// perbaikan di ViewModel dan UseCase tidak terkait dan bisa tetap dipakai.
// =============================================================================

/// Coordinator Transfer Landing — bentuknya mengikuti
/// `DetailDebitCardInfoCoordinator`: tidak ada `viewModel` maupun `useCase`
/// sebagai property, semuanya dibangun di dalam `createDestination()`.
///
/// Bedanya dari Detail Card Info: layar ini punya sembilan tujuan, dan
/// tautannya dibangun hanya untuk tujuan yang sedang dipilih. Konsekuensinya
/// tautan anak muncul di pohon saat tujuannya baru ditentukan — dalam keadaan
/// selection-nya sudah sama dengan tag-nya. `NavigationView` iOS 13–14 tidak
/// melakukan push untuk tautan seperti itu.
///
/// Karena itu tujuannya disimpan **dua tahap**: satu penanda menentukan tautan
/// mana yang dibangun, satu lagi menyalakan selection-nya satu putaran runloop
/// kemudian. Keduanya ada di ViewModel, bukan di sini — lihat catatan di atas.
struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    // PERUBAHAN: `@State private var useCase` dan `private let viewModel`
    // dihapus. Keduanya kini dibangun di `createDestination()`.
    //
    // PERUBAHAN: `@State private var destinationCoordinatorName` dihapus juga —
    // penggantinya ada di ViewModel, karena `@State` di sini tidak terlihat
    // oleh layar yang ter-push.

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

    // MARK: - Pembangunan layar

    // PERUBAHAN: seluruh method ini baru. Menggantikan `createViewModel()` yang
    // dulu dipanggil dari `body` pada setiap render.
    private func createDestination() -> some View {
        let useCase = createUseCase()
        let viewModel = createViewModel(useCase: useCase)

        // Dipasang di sini, bukan di `createUseCase()`, karena perutean menulis
        // state yang ada di ViewModel — jadi ViewModel harus sudah ada.
        //
        // `[weak]` di keduanya wajib: closure ini disimpan di `useCase.callback`,
        // dan `useCase` disimpan oleh ViewModel.
        useCase.callback.onSubmissionSucceed = { [weak useCase, weak viewModel] in
            guard let useCase = useCase, let viewModel = viewModel else { return }
            startDestinationCoordinator(for: useCase, on: viewModel)
        }

        return Screen {
            TransferLandingScreen(viewModel: viewModel)
        }
    }

    private func createUseCase() -> TransferLandingUseCase {
        // PERUBAHAN: objek baru, bukan `@State` yang dipakai ulang.
        let useCase = TransferLandingUseCase()

        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory

        return useCase
    }

    private func createViewModel(
        useCase: TransferLandingUseCase
    ) -> TransferLandingViewModel {
        // PERUBAHAN: objek baru, dan cabang `if selectionCoordinatorName != named`
        // yang dulu mengembalikan ViewModel kosong dihapus — dengan
        // `LazyNavigationLink` method ini hanya berjalan sekali, jadi cabang itu
        // tidak punya alasan lagi untuk ada.
        let viewModel = TransferLandingViewModel()

        // PERUBAHAN: menangkap `viewModel` secara weak. Closure ini disimpan di
        // ViewModel itu sendiri.
        viewModel.onCreateNavigationLinks = { [weak viewModel] in
            guard let viewModel = viewModel else {
                return DefaultValues.emptyAnyView
            }

            return createNavigationLinks(useCase: useCase, viewModel: viewModel)
        }

        viewModel.navigationBarViewModel.title = transferCart.targets.isEmpty
            ? R.string.navigationTitle.transferRecipient.text
            : String(
                format: R.string.navigationTitle.transferRecipientMultiple.text,
                transferCart.targets.count.nextNumber.ordinalText
            )

        viewModel.newRecipientMenuItemViewModel.analytic = AnalyticManager
            .instance
            .analytics
            .hitTransferLandingNewRecipient

        // PERUBAHAN: dulu `action = startNewRecipientCoordinator` dan
        // `analytic.parameters` diisi di sini. Keduanya membaca
        // `selectedTransferCategory`, dan itu hanya benar kalau method ini
        // berjalan pada setiap render. Sekarang ia berjalan sekali, jadi
        // pembacaannya dipindah ke dalam aksinya.
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

        viewModel.setUseCase(useCase)

        return viewModel
    }

    // MARK: - Perpindahan tujuan

    // PERUBAHAN: seluruh bagian ini menggantikan penulisan langsung ke
    // `destinationCoordinatorName`. Isi keputusannya sama; yang berubah hanya
    // ke mana hasilnya ditulis, dan bahwa penyalaannya dua tahap.
    private func startDestination(
        _ coordinatorName: String,
        on viewModel: TransferLandingViewModel
    ) {
        // Tahap 1 — tautannya masuk ke pohon, belum terpilih.
        viewModel.pendingDestinationCoordinatorName = coordinatorName

        // Tahap 2 — selection-nya dinyalakan setelah SwiftUI selesai
        // menyisipkan tautannya, sehingga `NavigationView` melihat perpindahan
        // dari tidak-terpilih ke terpilih.
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

    private func startPrivateAccountJourney(
        on viewModel: TransferLandingViewModel
    ) {
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

    // MARK: - Tautan navigasi

    // PERUBAHAN: membaca penanda dari ViewModel, bukan dari `@State` coordinator.
    // Sisanya identik dengan versi lama.
    private func createNavigationLinks(
        useCase: TransferLandingUseCase,
        viewModel: TransferLandingViewModel
    ) -> AnyView {
        if let destination = viewModel.pendingDestinationCoordinatorName,
           let navigationLink = navigationLinks(
               useCase: useCase,
               viewModel: viewModel
           )[destination] {
            return navigationLink()
        }

        return DefaultValues.emptyAnyView
    }

    // PERUBAHAN: ekspresi ini dulu ditulis sembilan kali dengan isi identik.
    // Namanya menyebut posisinya — nilai yang dioper ke parameter
    // `sourceCoordinatorName` milik anak — bukan kegunaannya, karena apa yang
    // dilakukan setiap anak dengan nilai itu berbeda-beda.
    //
    // Satu penyesuaian di badan `didSet`: ia kini membersihkan kedua penanda,
    // karena tujuannya disimpan dalam dua tahap.
    private func childSourceCoordinatorName(
        on viewModel: TransferLandingViewModel
    ) -> Binding<String?> {
        sourceCoordinatorName == nil
            ? $selectionCoordinatorName.didSet { [weak viewModel] _ in
                viewModel?.activeDestinationCoordinatorName = nil
                viewModel?.pendingDestinationCoordinatorName = nil
            }
            : $sourceCoordinatorName
    }

    // PERUBAHAN: kamusnya tetap kamus, isi setiap entri tetap sama. Yang berubah
    // hanya tiga hal yang berulang di kesembilan entri:
    //
    //   $destinationCoordinatorName  → viewModel.binding(\.activeDestinationCoordinatorName)
    //   ekspresi ternary panjang      → childSourceCoordinatorName(on:)
    //   $useCase.output.x             → useCase.binding(\.output.x)
    //
    // Ketiganya konsekuensi dari `useCase` dan penanda tujuan yang tidak lagi
    // `@State` di coordinator.
    private func navigationLinks(
        useCase: TransferLandingUseCase,
        viewModel: TransferLandingViewModel
    ) -> [String: TypeAliases.NavigationHandler] {
        let destinationSelection = viewModel.binding(
            \.activeDestinationCoordinatorName
        )
        let childSource = childSourceCoordinatorName(on: viewModel)

        return [
            TransferTransactionAmountCoordinator.named: {
                AnyView(
                    TransferTransactionAmountCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
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
                )
            },

            TransferDebitAccountSelectionCoordinator.named: {
                AnyView(
                    TransferDebitAccountSelectionCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
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
                )
            },

            DomesticTransferNewRecipientCoordinator.named: {
                AnyView(
                    DomesticTransferNewRecipientCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart
                    )
                )
            },

            ForeignTransferNewRecipientCoordinator.named: {
                AnyView(
                    ForeignTransferNewRecipientCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart
                    )
                )
            },

            ProxyTransferNewRecipientCoordinator.named: {
                AnyView(
                    ProxyTransferNewRecipientCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart
                    )
                )
            },

            TransferCurrencySelectionCoordinator.named: {
                AnyView(
                    TransferCurrencySelectionCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart,
                        recipientAccount: useCase.binding(\.output.recipientAccount),
                        recipientProfile: .constant(TransactionActorProfile()),
                        transferCategory: useCase.binding(\.output.transferCategory),
                        transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
                        predefineTransferPurpose: .constant(Option()),
                        isUsingValidateValasCutOffTime: .constant(true),
                        thematic: useCase.output.thematic
                    )
                )
            },

            BankSummaryCoordinator.named: {
                AnyView(
                    BankSummaryCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart,
                        bank: useCase.binding(\.output.bank),
                        transferCategory: useCase.binding(\.output.transferCategory),
                        transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod)
                    )
                )
            },

            TransferCountrySelectionCoordinator.named: {
                AnyView(
                    TransferCountrySelectionCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart,
                        transferCategory: useCase.binding(\.output.transferCategory),
                        transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod)
                    )
                )
            },

            TelegraphicRecipientFormCoordinator.named: {
                AnyView(
                    TelegraphicRecipientFormCoordinator(
                        selectionCoordinatorName: destinationSelection,
                        sourceCoordinatorName: childSource,
                        transferCart: $transferCart,
                        bank: useCase.binding(\.output.bank),
                        transferCategory: useCase.binding(\.output.transferCategory),
                        transferMethod: useCase.binding(\.output.predefineSelectedTransferMethod),
                        recipientAccount: useCase.binding(\.output.recipientAccount),
                        additionalInfo: useCase.binding(\.output.additionalInfo)
                    )
                )
            }
        ]
    }
}
