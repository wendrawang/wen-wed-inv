import Foundation

class TransferLandingUseCase: TransferRecipientUseCase {
    private(set) var repository = Repository()
    var input = Input()

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    override init() {
        super.init()

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    /// Sinkron — hanya memindahkan `input` ke `repository`, tanpa jaringan.
    /// Karena itu ia tidak menyalakan callback apa pun; ViewModel memanggil
    /// `setupView()` sendiri setelah ini. Jalur yang benar-benar mengambil data
    /// ada di `loadData(pageNumber:searchKeyword:)`.
    override func loadData() {
        repository.transferCategory = input.transferCategory
        repository.transferCart = input.transferCart

        guard repository.transferCategory == .unspecified else { return }

        repository.transferCategory = input
            .transferCart
            .availableNewTransferCategories
            .first ?? .unspecified
    }

    override func loadData(pageNumber: Int, searchKeyword: String) {
        // `renewIdentifier()` di sini memang disengaja: saat kata kunci berubah
        // atau halaman baru diminta, hasil permintaan sebelumnya harus dibuang.
        // Yang tidak boleh adalah coordinator ikut memanggilnya pada setiap
        // evaluasi body — itu membuang permintaan yang sedang berjalan tanpa
        // jejak. Lihat docs/SCREEN_PATTERN.md aturan 11.
        renewIdentifier()

        // `startFetchLoading()`, bukan `callback.onStartFetchLoading()`.
        // Helper-nya membungkus pemanggilan dalam DispatchQueue.main.async.
        // Di layar ini jalurnya melewati jaringan, jadi menulis `@Published`
        // dari thread selain main bukan lagi risiko teoretis.
        startFetchLoading()

        RecipientService(identifier).transferList(
            params: RequestTransferRecipientList(
                keyword: searchKeyword,
                transferCategory: repository.transferCategory,
                pagination: RequestPagination(
                    currentPage: pageNumber,
                    pageSize: PaginationPageSizes.large
                )
            ),
            onSuccess: inquiryRecipientSucceedHandlers[repository.transferCategory]
                ?? didInquiryRecipientsSucceed,
            onFailed: didFetchFailed
        )
    }

    override func flushData() {
        super.flushData()
        repository = Repository()
        output = Output()
    }

    func resetRecipientList() {
        repository.responseRecipientDomesticTransfers = [ResponseRecipientList()]
        repository.responseRecipientForeignTransfers = [ResponseRecipientList()]
        repository.responseRecipientProxyTransfers = [ResponseRecipientList()]
    }

    func startTransferToOwnAccount(
        bankAccount: BankAccount,
        transferCategory: TransferCategory
    ) {
        output = Output()
        output.recipientAccount = bankAccount
        output.transferCategory = transferCategory
        output.predefineSelectedTransferMethod = TransferMethod(
            code: transferCategory.serviceCode.rawValue
        )

        let sourceCurrency = input.transferCart.sourceAccount.firstCurrency

        let needsCutOffValidation = output.transferCategory == .privateAccount
            && !sourceCurrency.isEmpty
            && bankAccount.firstCurrency.code != sourceCurrency.code

        guard needsCutOffValidation else {
            startSubmissionSucceed(identifier)
            return
        }

        startFetchLoading()
        validateValasCutOffTime()
    }

    func setSelectedTransferCategory(_ category: TransferCategory) {
        repository.transferCategory = category
        output.transferCategory = category
    }

    // MARK: - Penanganan respons

    private func didInquiryRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        startFetchSucceed(requestorId)
    }

    private func didInquiryDomesticRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        guard requestorId == identifier else { return }

        repository.responseRecipientDomesticTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
    }

    private func didInquiryForeignRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        guard requestorId == identifier else { return }

        repository.responseRecipientForeignTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
    }

    private func didInquiryProxyRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        guard requestorId == identifier else { return }

        repository.responseRecipientProxyTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
    }
}

extension TransferLandingUseCase {
    class Input {
        var transferCategory: TransferCategory = .unspecified
        var transferCart = TransferCart()
    }

    class Repository {
        var responseRecipientDomesticTransfers = [ResponseRecipientList()]
        var responseRecipientForeignTransfers = [ResponseRecipientList()]
        var responseRecipientProxyTransfers = [ResponseRecipientList()]
        var transferCart = TransferCart()
        var transferCategory: TransferCategory = .unspecified
    }
}

extension TransferLandingUseCase {
    private var inquiryRecipientSucceedHandlers: [TransferCategory: TypeAliases.ResponseRecipientListHandler] {[
        TransferCategory.idr: didInquiryDomesticRecipientsSucceed,
        TransferCategory.valas: didInquiryForeignRecipientsSucceed,
        TransferCategory.proxy: didInquiryProxyRecipientsSucceed
    ]}
}
