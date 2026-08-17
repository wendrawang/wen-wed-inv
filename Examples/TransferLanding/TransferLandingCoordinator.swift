import SwiftUI

/// Coordinator Transfer Landing — bentuknya mengikuti
/// `DetailDebitCardInfoCoordinator`: tidak ada `viewModel` maupun `useCase`
/// sebagai property, semuanya dibangun di dalam `createDestination()` yang
/// hanya berjalan sekali saat layar di-push.
///
/// Ada satu perbedaan dari Detail Card Info, dan justifikasinya spesifik pada
/// layar ini. Detail Card Info adalah daun — tidak punya tujuan sama sekali.
/// Layar ini punya sembilan, dan tautannya dibangun hanya untuk tujuan yang
/// sedang dipilih supaya layar seberat ini tidak membangun sembilan cabang
/// sekaligus.
///
/// Konsekuensinya, tautan anak **muncul di pohon view saat tujuannya baru
/// ditentukan** — dan pada saat itu selection-nya sudah sama dengan tag-nya.
/// `NavigationView` di iOS 13–14 tidak melakukan push untuk tautan seperti itu;
/// ia perlu melihat perpindahan dari tidak-terpilih ke terpilih. Itulah kenapa
/// versi lama butuh `.id(destinationCoordinatorName)`, yang memaksa seluruh
/// layar dibangun ulang setiap kali berpindah.
///
/// Di sini masalahnya diselesaikan langsung, tanpa membangun ulang apa pun:
/// **tujuan disimpan di dua tahap.** `pendingDestinationCoordinatorName`
/// menentukan tautan mana yang ada di pohon; `activeDestinationCoordinatorName`
/// menyalakan selection-nya satu putaran runloop kemudian. Dengan begitu
/// SwiftUI melihat perpindahan yang dibutuhkannya, tautannya tetap hanya satu,
/// dan `.id()` tidak diperlukan lagi.
struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    /// Menentukan tautan mana yang **dibangun** di pohon view.
    @State private var pendingDestinationCoordinatorName: String?

    /// Menentukan tautan mana yang **terpilih**. Selalu menyusul
    /// `pendingDestinationCoordinatorName` satu putaran runloop kemudian.
    @State private var activeDestinationCoordinatorName: String?

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

        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory

        // `[weak useCase]` wajib: closure ini disimpan di `useCase.callback`,
        // jadi menangkapnya kuat berarti UseCase menahan dirinya sendiri.
        useCase.callback.onSubmissionSucceed = { [weak useCase] in
            guard let useCase = useCase else { return }
            startDestinationCoordinator(for: useCase)
        }

        return useCase
    }

    private func createViewModel(
        useCase: TransferLandingUseCase
    ) -> TransferLandingViewModel {
        let viewModel = TransferLandingViewModel()

        viewModel.onCreateNavigationLinks = {
            createNavigationLinks(useCase: useCase)
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

        // `[weak viewModel]` wajib: aksi ini disimpan di
        // `newRecipientMenuItemViewModel`, yang dimiliki ViewModel itu sendiri.
        //
        // Kategorinya dibaca di sini, saat tombol ditekan — bukan saat ViewModel
        // dibangun. Versi lama membacanya pada waktu konstruksi, dan itu aman
        // hanya karena `createViewModel()` dulu berjalan pada setiap render.
        // Sekarang ia berjalan sekali, jadi pembacaannya harus ditunda ke sini.
        viewModel.newRecipientMenuItemViewModel.action = { [weak viewModel] in
            guard let viewModel = viewModel else { return }

            startDestination(
                viewModel
                    .selectedTransferCategory
                    .newRecipientDestinationCoordinatorName
            )
        }

        viewModel.setUseCase(useCase)

        return viewModel
    }

    // MARK: - Perpindahan tujuan

    /// Menyalakan tujuan dalam dua tahap.
    ///
    /// Tahap pertama menyisipkan tautannya ke pohon view dalam keadaan belum
    /// terpilih. Tahap kedua, satu putaran runloop kemudian, menyalakan
    /// selection-nya — sehingga `NavigationView` melihat perpindahan dari
    /// tidak-terpilih ke terpilih dan melakukan push.
    ///
    /// Menyetel keduanya sekaligus tidak bekerja: tautannya akan muncul dalam
    /// keadaan sudah terpilih, dan tidak ada yang berubah dari sudut pandang
    /// `NavigationView`.
    private func startDestination(_ coordinatorName: String) {
        let active = $activeDestinationCoordinatorName

        pendingDestinationCoordinatorName = coordinatorName

        DispatchQueue.main.async {
            active.wrappedValue = coordinatorName
        }
    }

    private func startDestinationCoordinator(
        for useCase: TransferLandingUseCase
    ) {
        if useCase.output.transferCategory == .privateAccount {
            startPrivateAccountJourney()
            return
        }

        if useCase.output.transferCategory == .valas {
            startValasJourney(for: useCase)
            return
        }

        startDestination(TransferTransactionAmountCoordinator.named)
    }

    private func startPrivateAccountJourney() {
        if transferCart.targets.isEmpty {
            startDestination(TransferDebitAccountSelectionCoordinator.named)
            return
        }

        startDestination(TransferTransactionAmountCoordinator.named)
    }

    private func startValasJourney(for useCase: TransferLandingUseCase) {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            startDestination(TransferCurrencySelectionCoordinator.named)
            return
        }

        if useCase.output.bank.code.isEmpty {
            startDestination(TransferCountrySelectionCoordinator.named)
            return
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            startDestination(TelegraphicRecipientFormCoordinator.named)
            return
        }

        startDestination(BankSummaryCoordinator.named)
    }

    // MARK: - Tautan navigasi

    private func createNavigationLinks(
        useCase: TransferLandingUseCase
    ) -> AnyView {
        if let destination = pendingDestinationCoordinatorName,
           let navigationLink = navigationLinks(useCase: useCase)[destination] {
            return navigationLink()
        }

        return DefaultValues.emptyAnyView
    }

    /// Tujuan kembali untuk seluruh coordinator anak.
    ///
    /// Membersihkan **kedua** penyimpan tujuan, supaya tautannya keluar dari
    /// pohon dan tahap berikutnya kembali mulai dari keadaan belum terpilih.
    private var backTarget: Binding<String?> {
        if sourceCoordinatorName != nil {
            return $sourceCoordinatorName
        }

        return $selectionCoordinatorName.didSet { _ in
            activeDestinationCoordinatorName = nil
            pendingDestinationCoordinatorName = nil
        }
    }

    /// Membuat `Binding` ke sebuah field di `useCase.output`.
    ///
    /// Versi lama menulis `$useCase.output.recipientAccount`, yang hanya
    /// mungkin karena `useCase` disimpan sebagai `@State`. Di bentuk baru
    /// UseCase datang sebagai objek biasa yang dibangun di
    /// `createDestination()`, jadi binding-nya dibuat eksplisit.
    private func output<Value>(
        _ useCase: TransferLandingUseCase,
        _ keyPath: ReferenceWritableKeyPath<TransferLandingUseCase, Value>
    ) -> Binding<Value> {
        Binding(
            get: { useCase[keyPath: keyPath] },
            set: { useCase[keyPath: keyPath] = $0 }
        )
    }

    private func navigationLinks(
        useCase: TransferLandingUseCase
    ) -> [String: TypeAliases.NavigationHandler] {[
        TransferTransactionAmountCoordinator.named: {
            AnyView(
                TransferTransactionAmountCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    recipientAccount: output(useCase, \.output.recipientAccount),
                    recipientProfile: .constant(TransactionActorProfile()),
                    sourceAccount: $transferCart.sourceAccount,
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod),
                    transferCategory: output(useCase, \.output.transferCategory),
                    predefineTransferPurpose: .constant(Option()),
                    editTransferTarget: .constant(TransferTarget()),
                    additionalInfo: output(useCase, \.output.additionalInfo),
                    transferMethods: output(useCase, \.output.transferMethods),
                    thematic: useCase.output.thematic
                )
            )
        },

        TransferDebitAccountSelectionCoordinator.named: {
            AnyView(
                TransferDebitAccountSelectionCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    recipientAccount: output(useCase, \.output.recipientAccount),
                    recipientProfile: .constant(TransactionActorProfile()),
                    transferCategory: output(useCase, \.output.transferCategory),
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod),
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
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart
                )
            )
        },

        ForeignTransferNewRecipientCoordinator.named: {
            AnyView(
                ForeignTransferNewRecipientCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart
                )
            )
        },

        ProxyTransferNewRecipientCoordinator.named: {
            AnyView(
                ProxyTransferNewRecipientCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart
                )
            )
        },

        TransferCurrencySelectionCoordinator.named: {
            AnyView(
                TransferCurrencySelectionCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    recipientAccount: output(useCase, \.output.recipientAccount),
                    recipientProfile: .constant(TransactionActorProfile()),
                    transferCategory: output(useCase, \.output.transferCategory),
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod),
                    predefineTransferPurpose: .constant(Option()),
                    isUsingValidateValasCutOffTime: .constant(true),
                    thematic: useCase.output.thematic
                )
            )
        },

        BankSummaryCoordinator.named: {
            AnyView(
                BankSummaryCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    bank: output(useCase, \.output.bank),
                    transferCategory: output(useCase, \.output.transferCategory),
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod)
                )
            )
        },

        TransferCountrySelectionCoordinator.named: {
            AnyView(
                TransferCountrySelectionCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    transferCategory: output(useCase, \.output.transferCategory),
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod)
                )
            )
        },

        TelegraphicRecipientFormCoordinator.named: {
            AnyView(
                TelegraphicRecipientFormCoordinator(
                    selectionCoordinatorName: $activeDestinationCoordinatorName,
                    sourceCoordinatorName: backTarget,
                    transferCart: $transferCart,
                    bank: output(useCase, \.output.bank),
                    transferCategory: output(useCase, \.output.transferCategory),
                    transferMethod: output(useCase, \.output.predefineSelectedTransferMethod),
                    recipientAccount: output(useCase, \.output.recipientAccount),
                    additionalInfo: output(useCase, \.output.additionalInfo)
                )
            )
        }
    ]}
}
