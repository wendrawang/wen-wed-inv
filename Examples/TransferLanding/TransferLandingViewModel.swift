import SwiftUI

/// Struktur, urutan method, dan nama-namanya sama persis dengan aslinya.
/// Yang berubah hanya empat hal, semuanya di dalam badan method:
///
/// 1. Setiap closure yang disimpan memakai `[weak self]`.
/// 2. `setupRecipientList()` membangun ke array lokal lalu menerbitkan sekali.
/// 3. `selectedTransferCategory` menjaga nilai sebelum menerbitkan.
/// 4. `useCase` dijadikan `lazy` supaya nilai defaultnya tidak pernah dibuat.
class TransferLandingViewModel: PaginationScreenContentViewModel, TransactionalProtocol {
    @Published var accountHeadlineViewModels = [AccountHeadlineViewModel]()
    private(set) var privateAccountSelectionWidgetViewModel = BankAccountSelectionWidgetViewModel()
    private(set) var newRecipientMenuItemViewModel = MenuItemViewModel()
    private(set) var transferCategoryViewModel = CategoryViewModel()
    private(set) var bankSelectionAdapter = BankSelectionAdapter()

    /// `lazy` supaya nilai defaultnya tidak pernah benar-benar dibuat —
    /// `setUseCase(_:)` menulisnya sebelum ada yang membacanya.
    private(set) lazy var useCase = TransferLandingUseCase()

    private var selectedResponseRecipientTransfers: [ResponseRecipientList] {
        responseRecipientTransfers[
            useCase.repository.transferCategory
        ] ?? [ResponseRecipientList]()
    }

    /// Penjagaan nilai sebelum menerbitkan. Di `willSet` nilai lama masih
    /// tersedia, jadi penerbitan hanya terjadi kalau kategorinya berubah.
    var selectedTransferCategory: TransferCategory = .unspecified {
        willSet {
            if newValue == selectedTransferCategory {
                return
            }

            self.objectWillChange.send()
        }
    }

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    override init() {
        super.init()
        analytic = AnalyticManager.instance.analytics.visitTransferLanding

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    override func initState() {
        super.initState()
        searchBarViewModel.textFieldViewModel.activateDebounceInput()
    }

    override func loadData() {
        useCase.requestLoadData()
        setupView()
        if selectedResponseRecipientTransfers.isEmpty {
            return
        }
        super.loadData()
    }

    override func loadData(pageNumber: Int) {
        super.loadData(pageNumber: pageNumber)
        useCase.requestLoadData(
            pageNumber: pageNumber,
            searchKeyword: searchBarViewModel.searchKeyword
        )
    }

    override func reloadData() {
        accountHeadlineViewModels.removeAll()
        useCase.resetRecipientList()
        super.reloadData()
    }

    /// Membangun ke array lokal, lalu menerbitkan sekali di akhir.
    ///
    /// Versi lama menulis langsung ke `accountHeadlineViewModels` — `removeAll()`
    /// lalu `append()` di dalam loop — sehingga satu halaman berisi 20 kontak
    /// menerbitkan 22 invalidasi berturut-turut. Karena invalidasi
    /// `ObservableObject` bersifat object-level, tiap satunya meng-invalidasi
    /// seluruh layar.
    private func setupRecipientList() {
        var accountHeadlineViewModels = [AccountHeadlineViewModel]()

        for data in selectedResponseRecipientTransfers {
            for bankContact in data.bankContacts {
                accountHeadlineViewModels.append(
                    makeAccountHeadlineViewModel(bankContact)
                )
            }

            infiniteScrollViewModel.updatePagination(data.pagination)
        }

        if searchBarViewModel.searchKeyword.isEmpty {
            accountHeadlineViewModels = accountHeadlineViewModels.transformToSectionedItems()
        }

        self.accountHeadlineViewModels = accountHeadlineViewModels

        if accountHeadlineViewModels.isEmpty {
            setupEmptyState()
        }
    }

    private func makeAccountHeadlineViewModel(
        _ bankContact: BankContact
    ) -> AccountHeadlineViewModel {
        let accountHeadlineViewModel = bankContact.convertToAccountHeadlineViewModel()

        // `[weak self]` di kedua closure. Keduanya disimpan pada objek yang
        // kemudian masuk ke `accountHeadlineViewModels` — property milik
        // ViewModel ini sendiri — sehingga tanpa `weak`, setiap baris menahan
        // ViewModel dan daftar 100 kontak berarti 200 lingkaran.
        accountHeadlineViewModel.showFavoriteButton(
            action: { [weak self] in
                self?.switchFavoriteState(bankContact)
            }
        )

        accountHeadlineViewModel.action = { [weak self] in
            self?.startSubmission(recipientContact: bankContact)
        }

        accountHeadlineViewModel.isEnabled = true
        accountHeadlineViewModel.accessibilityIdentifier = String(
            format: AutomationIdentifierManager
                .instance
                .identifiers
                .buttonSaveBeneficiary,
            bankContact.accountInfo.accountNumber
        )

        return accountHeadlineViewModel
    }

    private func switchFavoriteState(_ bankContact: BankContact) {
        if bankContact.isFavorite {
            var message = DialogCodes.Client.removeRecipientFromFavorite.dialogMessage
            message.secondaryButton.customAction = { [weak self] in
                self?.useCase.switchFavoriteState(bankContact: bankContact)
            }
            messageHandler(message, DefaultValues.emptyAnyDictionary)
            return
        }

        useCase.switchFavoriteState(bankContact: bankContact)
    }

    private func startSubmission(recipientContact: BankContact) {
        var event = AnalyticManager.instance.analytics.startInquiryTransferSavedRecipient
        event.parameters = [
            .categoryTitle: selectedTransferCategory.title
        ]

        AnalyticManager.instance.track(event)

        useCase.startSubmission(
            data: TransferRecipientUseCase.SubmissionData(
                bank: recipientContact.accountInfo.bank.bankType == .domestic
                    ? recipientContact.accountInfo.bank
                    : Bank(),
                identifier: recipientContact.identifier,
                nickname: recipientContact.nickname,
                accountName: recipientContact.accountInfo.accountName,
                accountFullname: recipientContact.transferInfo.accountFullname,
                accountNumber: recipientContact.accountInfo.accountNumber,
                swiftCode: recipientContact.accountInfo.bank.bankType == .domestic
                    ? DefaultValues.emptyString
                    : recipientContact.accountInfo.bank.code,
                transferCategory: recipientContact.transferInfo.transferCategory,
                nationality: recipientContact.transferInfo.citizenship,
                nccValue: recipientContact.transferInfo.nccValue,
                address: recipientContact.address,
                domicile: recipientContact.domicile,
                accountCategory: recipientContact.accountCategory
            )
        )
    }

    private func setupView() {
        setupTransferCategoryViewModel()
        setupPrivateBankAccountSelectionWidgetViewModel()
        setupNewRecipientMenuItemViewModel()
        setupMultipleTransfer()
    }

    override func setupEmptyState() {
        emptyStateViewModel.type = .emptySearchResult
        emptyStateViewModel.title = R.string.emptyState.searchNotFound.text
        emptyStateViewModel.subtitle = R.string.emptyState.pleaseRecheckKeyword.text
        emptyStateViewModel.isHidden = searchBarViewModel.searchKeyword.isEmpty
    }

    override func flushData() {
        super.flushData()
        useCase.flushData()
        selectedTransferCategory = .unspecified
        bankSelectionAdapter = BankSelectionAdapter()
        accountHeadlineViewModels.removeAll()
        transferCategoryViewModel.categoryItemViewModels.removeAll()
        privateAccountSelectionWidgetViewModel.removeAllBankAccountItemViewModels()
    }

    override func setupSearchBarViewModel() {
        searchBarViewModel.textFieldViewModel.style = SearchTextFieldViewStyle()
        searchBarViewModel.textFieldViewModel.leftIconName = R.image.iconColoredSearch.name
        searchBarViewModel.textFieldViewModel.isBottomLineVisible = false
        searchBarViewModel.textFieldViewModel.placeholder = R.string.field.searchRecipientName.text
        searchBarViewModel.onStartSearch = { [weak self] _ in
            self?.reloadData()
        }
        searchBarViewModel.textFieldViewModel.inputComponent.accessibilityIdentifier = AutomationIdentifierManager
            .instance
            .identifiers
            .fieldInputSearch
    }

    private func setupNewRecipientMenuItemViewModel() {
        newRecipientMenuItemViewModel.title = R.string.menu.newRecipientTitle.text
        newRecipientMenuItemViewModel.subtitles = [R.string.menu.newRecipientSubtitle.text]
        newRecipientMenuItemViewModel.horizontalPadding = Spaces.small
        newRecipientMenuItemViewModel.rightIconSize = IconSizes.medium
        newRecipientMenuItemViewModel.isBottomSeparatorVisible = false
        newRecipientMenuItemViewModel.imageViewModel.setImage(named: R.image.iconNewRecipient.name)
        newRecipientMenuItemViewModel.accessibilityIdentifier = AutomationIdentifierManager
            .instance
            .identifiers
            .buttonNewRecipient
    }

    private func setupMultipleTransfer() {
        if useCase.repository.transferCart.targets.isEmpty {
            return
        }

        if useCase.repository.transferCart.sourceAccount.firstCurrency.code != Currencies.idr.code {
            privateAccountSelectionWidgetViewModel.filteredCurrencyCodes = [
                Currencies.idr.code,
                useCase.repository.transferCart.sourceAccount.firstCurrency.code
            ]
        }

        privateAccountSelectionWidgetViewModel.excludedBankAccounts = useCase.repository.transferCart
            .sourceAccount
            .isEmpty ? [] : [useCase.repository.transferCart.sourceAccount]

        setupTransactionSummaryCardViewModels(
            useCase.repository.transferCart.generateSummaryCardViewModels()
        )
    }

    func setUseCase(_ useCase: TransferLandingUseCase) {
        // Delapan closure di bawah ini dulu dipasang sebagai referensi method
        // (`onFetchSucceed = setupRecipientList`), yang menangkap `self` secara
        // kuat. Karena ViewModel menyimpan UseCase dan UseCase menyimpan
        // closure-nya, keduanya saling menahan dan tidak pernah dilepas.
        useCase.callback.onStartSubmissionLoading = { [weak self] in
            self?.startScreenLoading()
        }
        useCase.callback.onStopSubmissionLoading = { [weak self] in
            self?.stopScreenLoading()
        }
        useCase.callback.onStartSwitchFavoriteLoading = { [weak self] in
            self?.startScreenLoading()
        }
        useCase.callback.onStopSwitchFavoriteLoading = { [weak self] in
            self?.stopScreenLoading()
        }
        useCase.callback.onSwitchFavoriteSucceed = { [weak self] in
            self?.reloadData()
        }
        useCase.callback.onSubmissionFailed = { [weak self] error in
            self?.didReceiveError(error)
        }
        useCase.callback.onFetchSucceed = { [weak self] in
            self?.setupRecipientList()
        }
        useCase.callback.onFetchFailed = { [weak self] error in
            self?.didReceiveError(error)
        }

        // Dua ini sengaja dibiarkan apa adanya: keduanya menangkap
        // `infiniteScrollViewModel`, bukan `self`, dan `infiniteScrollViewModel`
        // tidak memegang ViewModel. Tidak ada lingkaran yang terbentuk.
        useCase.callback.onStartFetchLoading = infiniteScrollViewModel.startLoading
        useCase.callback.onStopFetchLoading = infiniteScrollViewModel.stopLoading

        self.useCase = useCase
    }
}

extension TransferLandingViewModel {
    func setupPrivateBankAccountSelectionWidgetViewModel() {
        privateAccountSelectionWidgetViewModel.adapter = BeneficiaryAccountSelectionAdapter(
            analytic: AnalyticManager.instance.analytics.hitTransferAccountSelect
        )

        privateAccountSelectionWidgetViewModel.onReceiveError = { [weak self] error in
            self?.messageHandler(error.message, DefaultValues.emptyAnyDictionary)
        }

        privateAccountSelectionWidgetViewModel.setHeight(.infinity)
        privateAccountSelectionWidgetViewModel.onChangeValue = { [weak self] bankAccount in
            self?.didSelectedPrivateBankAccount(bankAccount)
        }
    }

    private func didSelectedPrivateBankAccount(_ bankAccount: BankAccount) {
        useCase.startTransferToOwnAccount(
            bankAccount: bankAccount,
            transferCategory: selectedTransferCategory
        )
    }
}

extension TransferLandingViewModel {
    func setupTransferCategoryViewModel() {
        if !transferCategoryViewModel.categoryItemViewModels.isEmpty {
            return
        }

        selectedTransferCategory = useCase.repository.transferCategory
        transferCategoryViewModel.categoryItemViewModels = useCase
            .repository
            .transferCart
            .availableNewTransferCategories
            .convertToCategoryItemViewModels()

        transferCategoryViewModel.onSelectedItem = { [weak self] item in
            self?.onSelectedCategoryItem(item)
        }

        transferCategoryViewModel.selectByValue(selectedTransferCategory.rawValue)
    }

    private func onSelectedCategoryItem(_ item: CategoryItemViewModel) {
        let newSelectedTransferCategory = TransferCategory(
            rawValue: item.value
        ) ?? .unspecified

        if selectedTransferCategory == newSelectedTransferCategory {
            return
        }

        UIApplication.shared.endEditing()
        selectedTransferCategory = newSelectedTransferCategory
        searchBarViewModel.flushData()
        bankSelectionAdapter.removeAllData()
        bankSelectionAdapter.isValas = selectedTransferCategory == .valas
        privateAccountSelectionWidgetViewModel.clearSelection()
        useCase.setSelectedTransferCategory(selectedTransferCategory)
        reloadData()
    }
}

extension TransferLandingViewModel {
    private var responseRecipientTransfers: [TransferCategory: [ResponseRecipientList]] {[
        TransferCategory.idr: useCase.repository.responseRecipientDomesticTransfers,
        TransferCategory.valas: useCase.repository.responseRecipientForeignTransfers,
        TransferCategory.proxy: useCase.repository.responseRecipientProxyTransfers
    ]}
}
