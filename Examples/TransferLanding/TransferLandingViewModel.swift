import SwiftUI

class TransferLandingViewModel: PaginationScreenContentViewModel, TransactionalProtocol {
    /// Tetap `var`, bukan `private(set)`.
    ///
    /// `InfiniteScrollListView` menerimanya sebagai `Binding` dua arah, dan
    /// saya tidak bisa memastikan ia tidak pernah menulis balik. Menguncinya
    /// jadi `private(set)` akan memaksa pemakaian `.constant(...)` di layar,
    /// yang membuang tulisan itu tanpa suara.
    @Published var accountHeadlineViewModels = [AccountHeadlineViewModel]()

    private(set) var privateAccountSelectionWidgetViewModel = BankAccountSelectionWidgetViewModel()
    private(set) var newRecipientMenuItemViewModel = MenuItemViewModel()
    private(set) var transferCategoryViewModel = CategoryViewModel()
    private(set) var bankSelectionAdapter = BankSelectionAdapter()

    /// `lazy` supaya nilai defaultnya tidak pernah benar-benar dibuat —
    /// `setUseCase(_:)` menulisnya sebelum ada yang membacanya. Lihat
    /// docs/SCREEN_PATTERN.md aturan 1.
    private(set) lazy var useCase = TransferLandingUseCase()

    /// Diisi coordinator. ViewModel memberi tahu kategori yang sedang terpilih;
    /// coordinator yang memutuskan tujuannya.
    var onStartNewRecipient: (TransferCategory) -> Void = { _ in }

    /// Penjagaan nilai di `willSet`. Di titik itu nilai lama masih tersedia,
    /// jadi penerbitan hanya terjadi kalau kategorinya benar-benar berubah.
    ///
    /// Akses tetap `var`, tidak dikunci `private(set)`. Property ini mungkin
    /// dipakai `TransactionalProtocol` atau ditulis dari luar di tempat yang
    /// belum saya lihat, dan penjagaan nilainya tetap bekerja tanpa penguncian
    /// itu. Yang dituju perbaikan ini adalah penerbitannya, bukan akses tulis.
    var selectedTransferCategory: TransferCategory = .unspecified {
        willSet {
            guard newValue != selectedTransferCategory else { return }
            objectWillChange.send()
        }
    }

    private var selectedResponseRecipientTransfers: [ResponseRecipientList] {
        responseRecipientTransfers[useCase.repository.transferCategory]
            ?? [ResponseRecipientList]()
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

    // MARK: - Siklus data

    override func initState() {
        super.initState()
        searchBarViewModel.textFieldViewModel.activateDebounceInput()
    }

    override func loadData() {
        useCase.requestLoadData()

        // Aman dipanggil langsung di sini: `loadData()` pada UseCase ini
        // sinkron — ia hanya menyalin `input` ke `repository` — sehingga
        // repository sudah terisi saat baris berikutnya berjalan. Bagian yang
        // datang dari jaringan diisi `setupRecipientList()` lewat callback.
        setupView()

        guard !selectedResponseRecipientTransfers.isEmpty else { return }

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

    override func flushData() {
        super.flushData()

        useCase.flushData()
        selectedTransferCategory = .unspecified
        bankSelectionAdapter = BankSelectionAdapter()
        accountHeadlineViewModels.removeAll()
        transferCategoryViewModel.categoryItemViewModels.removeAll()
        privateAccountSelectionWidgetViewModel.removeAllBankAccountItemViewModels()
    }

    func setUseCase(_ useCase: TransferLandingUseCase) {
        // Delapan dari sepuluh callback ini dulu dipasang sebagai referensi
        // method (`onFetchSucceed = setupRecipientList`), yang menangkap `self`
        // secara kuat. Karena ViewModel menyimpan UseCase dan UseCase menyimpan
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

        // Dua ini sengaja dibiarkan tanpa `[weak self]`: keduanya menangkap
        // `infiniteScrollViewModel`, bukan `self`, dan `infiniteScrollViewModel`
        // tidak memegang ViewModel. Tidak ada lingkaran yang terbentuk.
        useCase.callback.onStartFetchLoading = infiniteScrollViewModel.startLoading
        useCase.callback.onStopFetchLoading = infiniteScrollViewModel.stopLoading

        self.useCase = useCase
    }

    // MARK: - Pengisian tampilan

    /// Bagian yang tidak bergantung pada hasil jaringan.
    private func setupView() {
        setupTransferCategoryViewModel()
        setupPrivateBankAccountSelectionWidgetViewModel()
        setupNewRecipientMenuItemViewModel()
        setupMultipleTransfer()
    }

    /// Bagian yang datang dari jaringan. Hanya dipicu `onFetchSucceed`.
    ///
    /// Perubahan pentingnya ada di baris terakhir. Versi lama menulis langsung
    /// ke `accountHeadlineViewModels` — `removeAll()` lalu `append()` di dalam
    /// loop — sehingga satu halaman berisi 20 kontak menerbitkan 22 invalidasi
    /// berturut-turut, dan karena invalidasi `ObservableObject` bersifat
    /// object-level, tiap satunya meng-invalidasi seluruh layar.
    private func setupRecipientList() {
        var models = [AccountHeadlineViewModel]()

        for data in selectedResponseRecipientTransfers {
            for bankContact in data.bankContacts {
                models.append(makeAccountHeadlineViewModel(bankContact))
            }

            infiniteScrollViewModel.updatePagination(data.pagination)
        }

        if searchBarViewModel.searchKeyword.isEmpty {
            models = models.transformToSectionedItems()
        }

        accountHeadlineViewModels = models

        if models.isEmpty {
            setupEmptyState()
        }
    }

    private func makeAccountHeadlineViewModel(
        _ bankContact: BankContact
    ) -> AccountHeadlineViewModel {
        let viewModel = bankContact.convertToAccountHeadlineViewModel()

        // Dua closure ini disimpan di objek yang nanti masuk ke
        // `accountHeadlineViewModels` — property milik ViewModel ini sendiri.
        // Tanpa `[weak self]`, setiap baris menahan ViewModel, sehingga daftar
        // 100 kontak berarti 200 lingkaran.
        viewModel.showFavoriteButton(
            action: { [weak self] in
                self?.switchFavoriteState(bankContact)
            }
        )

        viewModel.action = { [weak self] in
            self?.startSubmission(recipientContact: bankContact)
        }

        viewModel.isEnabled = true
        viewModel.accessibilityIdentifier = String(
            format: AutomationIdentifierManager
                .instance
                .identifiers
                .buttonSaveBeneficiary,
            bankContact.accountInfo.accountNumber
        )

        return viewModel
    }

    override func setupEmptyState() {
        emptyStateViewModel.type = .emptySearchResult
        emptyStateViewModel.title = R.string.emptyState.searchNotFound.text
        emptyStateViewModel.subtitle = R.string.emptyState.pleaseRecheckKeyword.text
        emptyStateViewModel.isHidden = searchBarViewModel.searchKeyword.isEmpty
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

        // Analitiknya dirakit **saat aksi dijalankan**, bukan saat ViewModel
        // dibangun. Versi lama merakitnya di coordinator pada waktu konstruksi,
        // yaitu sebelum `loadData()` pernah berjalan, sehingga parameter
        // kategorinya selalu terkirim sebagai `.unspecified`.
        newRecipientMenuItemViewModel.action = { [weak self] in
            guard let self = self else { return }

            var event = AnalyticManager
                .instance
                .analytics
                .hitTransferLandingNewRecipient

            event.parameters = [
                .categoryTitle: self.selectedTransferCategory.rawValue
            ]

            AnalyticManager.instance.track(event)

            self.onStartNewRecipient(self.selectedTransferCategory)
        }
    }

    private func setupMultipleTransfer() {
        guard !useCase.repository.transferCart.targets.isEmpty else { return }

        let sourceAccount = useCase.repository.transferCart.sourceAccount

        if sourceAccount.firstCurrency.code != Currencies.idr.code {
            privateAccountSelectionWidgetViewModel.filteredCurrencyCodes = [
                Currencies.idr.code,
                sourceAccount.firstCurrency.code
            ]
        }

        privateAccountSelectionWidgetViewModel.excludedBankAccounts = sourceAccount.isEmpty
            ? []
            : [sourceAccount]

        setupTransactionSummaryCardViewModels(
            useCase.repository.transferCart.generateSummaryCardViewModels()
        )
    }

    // MARK: - Aksi

    private func switchFavoriteState(_ bankContact: BankContact) {
        guard bankContact.isFavorite else {
            useCase.switchFavoriteState(bankContact: bankContact)
            return
        }

        var message = DialogCodes.Client.removeRecipientFromFavorite.dialogMessage

        message.secondaryButton.customAction = { [weak self] in
            self?.useCase.switchFavoriteState(bankContact: bankContact)
        }

        messageHandler(message, DefaultValues.emptyAnyDictionary)
    }

    private func startSubmission(recipientContact: BankContact) {
        var event = AnalyticManager.instance.analytics.startInquiryTransferSavedRecipient
        event.parameters = [.categoryTitle: selectedTransferCategory.title]

        AnalyticManager.instance.track(event)

        let isDomestic = recipientContact.accountInfo.bank.bankType == .domestic

        useCase.startSubmission(
            data: TransferRecipientUseCase.SubmissionData(
                bank: isDomestic ? recipientContact.accountInfo.bank : Bank(),
                identifier: recipientContact.identifier,
                nickname: recipientContact.nickname,
                accountName: recipientContact.accountInfo.accountName,
                accountFullname: recipientContact.transferInfo.accountFullname,
                accountNumber: recipientContact.accountInfo.accountNumber,
                swiftCode: isDomestic
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
}

// MARK: - Pemilihan rekening sendiri

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
            self?.didSelectPrivateBankAccount(bankAccount)
        }
    }

    private func didSelectPrivateBankAccount(_ bankAccount: BankAccount) {
        useCase.startTransferToOwnAccount(
            bankAccount: bankAccount,
            transferCategory: selectedTransferCategory
        )
    }
}

// MARK: - Kategori transfer

extension TransferLandingViewModel {
    func setupTransferCategoryViewModel() {
        guard transferCategoryViewModel.categoryItemViewModels.isEmpty else { return }

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
        let newSelectedTransferCategory = TransferCategory(rawValue: item.value)
            ?? .unspecified

        guard selectedTransferCategory != newSelectedTransferCategory else { return }

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
