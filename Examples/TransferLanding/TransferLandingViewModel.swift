import SwiftUI

/// Struktur, urutan method, dan nama-namanya sama persis dengan aslinya.
/// Setiap baris yang berubah diberi komentar `PERUBAHAN:` di atasnya, jadi
/// bisa diambil satu-satu tanpa mengganti seluruh file.
///
/// Ringkasnya ada lima:
///
/// 1. Dua penanda tujuan navigasi pindah ke sini dari coordinator.
/// 2. Setiap closure yang disimpan memakai `[weak self]`.
/// 3. `setupRecipientList()` membangun ke array lokal lalu menerbitkan sekali,
///    dan baris yang sudah ada dipakai ulang supaya posisi scroll bertahan
///    saat halaman berikutnya datang.
/// 4. `selectedTransferCategory` menjaga nilai sebelum menerbitkan.
/// 5. `useCase` dijadikan `lazy` supaya nilai defaultnya tidak pernah dibuat.
class TransferLandingViewModel: PaginationScreenContentViewModel, TransactionalProtocol {
    @Published var accountHeadlineViewModels = [AccountHeadlineViewModel]()
    private(set) var privateAccountSelectionWidgetViewModel = BankAccountSelectionWidgetViewModel()
    private(set) var newRecipientMenuItemViewModel = MenuItemViewModel()
    private(set) var transferCategoryViewModel = CategoryViewModel()
    private(set) var bankSelectionAdapter = BankSelectionAdapter()

    // PERUBAHAN: dua penanda tujuan navigasi, sebelumnya `@State` di
    // coordinator.
    //
    // Harus di sini, bukan di coordinator. `LazyNavigationLink` membekukan
    // destination, dan layar yang ter-push hanya mengamati ViewModel — ia tidak
    // pernah tahu `@State` coordinator berubah. Menaruhnya di sini membuat
    // penulisannya benar-benar memicu evaluasi ulang `renderNavigationLinks()`.
    //
    // Dipisah dua karena `NavigationView` iOS 13–14 tidak melakukan push untuk
    // tautan yang disisipkan dalam keadaan sudah terpilih. Yang pertama
    // menentukan tautan mana yang dibangun; yang kedua menyalakan selection-nya
    // satu putaran runloop kemudian.

    /// Menentukan tautan tujuan mana yang **dibangun** di pohon view.
    @Published var pendingDestinationCoordinatorName: String?

    /// Menentukan tautan tujuan mana yang **terpilih**.
    @Published var activeDestinationCoordinatorName: String?

    // PERUBAHAN: `lazy`, supaya nilai defaultnya tidak pernah benar-benar
    // dibuat — `setUseCase(_:)` menulisnya sebelum ada yang membacanya.
    private(set) lazy var useCase = TransferLandingUseCase()

    private var selectedResponseRecipientTransfers: [ResponseRecipientList] {
        responseRecipientTransfers[
            useCase.repository.transferCategory
        ] ?? [ResponseRecipientList]()
    }

    // PERUBAHAN: penjagaan nilai sebelum menerbitkan. Di `willSet` nilai lama
    // masih tersedia, jadi penerbitan hanya terjadi kalau kategorinya berubah.
    // Sebelumnya `objectWillChange.send()` dipanggil tanpa syarat.
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

        // PERUBAHAN: probe lifecycle, hanya di build Debug.
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
        // PERUBAHAN: arah penjagaannya dibalik kembali ke bentuk aslinya.
        //
        // Saya sempat menulisnya terbalik (`isEmpty` → return), dan akibatnya
        // `super.loadData()` tidak pernah tercapai pada pembukaan pertama —
        // saat itulah daftarnya justru masih kosong. Layar terbuka tanpa
        // memuat halaman pertama.
        //
        // Yang benar: kalau datanya sudah ada di repository (kembali dari
        // layar tujuan, misalnya), tidak perlu memuat ulang. Kalau kosong,
        // teruskan ke `super` supaya halaman pertama diambil.
        if !selectedResponseRecipientTransfers.isEmpty {
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
        // PERUBAHAN: cache baris ikut dikosongkan, sepasang dengan baris di atas.
        accountHeadlineViewModelCache.removeAll()
        useCase.resetRecipientList()
        super.reloadData()
    }

    // PERUBAHAN: membangun ke array lokal, lalu menerbitkan sekali di akhir.
    //
    // Versi lama menulis langsung ke `accountHeadlineViewModels` —
    // `removeAll()` lalu `append()` di dalam loop — sehingga satu halaman
    // berisi 20 kontak menerbitkan 22 invalidasi berturut-turut. Karena
    // invalidasi `ObservableObject` bersifat object-level, tiap satunya
    // meng-invalidasi seluruh layar.
    private func setupRecipientList() {
        var accountHeadlineViewModels = [AccountHeadlineViewModel]()

        for data in selectedResponseRecipientTransfers {
            for bankContact in data.bankContacts {
                // PERUBAHAN: lewat cache, bukan langsung ke `make…`.
                accountHeadlineViewModels.append(
                    accountHeadlineViewModel(for: bankContact)
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

    // PERUBAHAN: baris yang sudah pernah dibangun dipakai lagi.
    //
    // `selectedResponseRecipientTransfers` menampung **semua** halaman yang
    // sudah diterima, jadi setiap kali halaman baru datang, loop di atas
    // melewati halaman 1 sampai N. Tanpa cache, baris halaman 1 dibangun ulang
    // sebagai objek baru — dan karena `AccountHeadlineViewModel` adalah class,
    // objek baru berarti identitas baru, sehingga list dianggap berganti
    // seluruhnya dan posisi scroll kembali ke atas tepat saat halaman 2 masuk.
    //
    // Cache dikosongkan bersamaan dengan `accountHeadlineViewModels.removeAll()`
    // di `reloadData()` dan `flushData()`. Itu penting: `bankContact` ikut
    // tertangkap di dalam closure baris, jadi setelah favorit di-toggle atau
    // kata kunci berubah, barisnya memang harus dibangun ulang — dan kedua
    // jalur itu sama-sama lewat `reloadData()`.
    //
    // Kuncinya sengaja distringkan lewat interpolasi supaya tidak bergantung
    // pada tipe `BankContact.identifier`. Kalau di proyek Anda `identifier`
    // sudah berupa `String` yang unik, pemanggilan `String(describing:)`-nya
    // boleh dihapus.
    private var accountHeadlineViewModelCache = [String: AccountHeadlineViewModel]()

    // PERUBAHAN: pembungkus cache untuk `makeAccountHeadlineViewModel`.
    private func accountHeadlineViewModel(
        for bankContact: BankContact
    ) -> AccountHeadlineViewModel {
        let key = String(describing: bankContact.identifier)

        if let cachedAccountHeadlineViewModel = accountHeadlineViewModelCache[key] {
            return cachedAccountHeadlineViewModel
        }

        let accountHeadlineViewModel = makeAccountHeadlineViewModel(bankContact)
        accountHeadlineViewModelCache[key] = accountHeadlineViewModel
        return accountHeadlineViewModel
    }

    // PERUBAHAN: isi loop dipindah ke fungsi ini supaya `[weak self]`-nya
    // terbaca. Isinya sama persis dengan versi lama.
    private func makeAccountHeadlineViewModel(
        _ bankContact: BankContact
    ) -> AccountHeadlineViewModel {
        let accountHeadlineViewModel = bankContact.convertToAccountHeadlineViewModel()

        // PERUBAHAN: `[weak self]` di kedua closure. Keduanya disimpan pada
        // objek yang kemudian masuk ke `accountHeadlineViewModels` — property
        // milik ViewModel ini sendiri — sehingga tanpa `weak`, setiap baris
        // menahan ViewModel dan daftar 100 kontak berarti 200 lingkaran.
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
            // PERUBAHAN: `[weak self]`.
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
        // PERUBAHAN: cache baris ikut dikosongkan, sepasang dengan baris di atas.
        accountHeadlineViewModelCache.removeAll()
        transferCategoryViewModel.categoryItemViewModels.removeAll()
        privateAccountSelectionWidgetViewModel.removeAllBankAccountItemViewModels()
    }

    override func setupSearchBarViewModel() {
        searchBarViewModel.textFieldViewModel.style = SearchTextFieldViewStyle()
        searchBarViewModel.textFieldViewModel.leftIconName = R.image.iconColoredSearch.name
        searchBarViewModel.textFieldViewModel.isBottomLineVisible = false
        searchBarViewModel.textFieldViewModel.placeholder = R.string.field.searchRecipientName.text
        // PERUBAHAN: `[weak self]`.
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
        // PERUBAHAN: delapan closure di bawah ini dulu dipasang sebagai referensi method
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

        // PERUBAHAN: `[weak self]`.
        privateAccountSelectionWidgetViewModel.onReceiveError = { [weak self] error in
            self?.messageHandler(error.message, DefaultValues.emptyAnyDictionary)
        }

        privateAccountSelectionWidgetViewModel.setHeight(.infinity)
        // PERUBAHAN: `[weak self]`.
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

        // PERUBAHAN: `[weak self]`.
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

// PERUBAHAN: konformansi baru, supaya coordinator bisa menulis
// `viewModel.binding(\.activeDestinationCoordinatorName)`.
//
// Kalau nanti dibutuhkan di banyak layar, pindahkan ke
// `ScreenContentViewModel` supaya seluruh ViewModel ikut.
extension TransferLandingViewModel: PropertyBindable {}
