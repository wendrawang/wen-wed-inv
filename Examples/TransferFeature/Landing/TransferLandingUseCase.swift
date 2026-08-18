import Foundation

/// Bentuknya sama persis dengan aslinya. Yang berubah hanya dua baris
/// `callback.onStartFetchLoading()` menjadi `startFetchLoading()`, ditambah
/// probe lifecycle.
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

    override func loadData() {
        repository.transferCategory = input.transferCategory
        repository.transferCart = input.transferCart
        if repository.transferCategory == .unspecified {
            repository.transferCategory = input
                .transferCart
                .availableNewTransferCategories
                .first ?? .unspecified
        }
    }

    override func loadData(pageNumber: Int, searchKeyword: String) {
        renewIdentifier()

        // `startFetchLoading()`, bukan `callback.onStartFetchLoading()`.
        // Helper-nya membungkus pemanggilan dalam DispatchQueue.main.async.
        // Jalur di bawah ini melewati jaringan, jadi menulis `@Published` dari
        // thread selain main bukan risiko teoretis.
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
        if requestorId != identifier {
            return
        }

        repository.responseRecipientDomesticTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
    }

    private func didInquiryForeignRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        if requestorId != identifier {
            return
        }

        repository.responseRecipientForeignTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
    }

    private func didInquiryProxyRecipientsSucceed(
        _ response: ResponseRecipientList,
        _ requestorId: UUID
    ) {
        if requestorId != identifier {
            return
        }

        repository.responseRecipientProxyTransfers.appendIfPageNotExist(response)
        startFetchSucceed(requestorId)
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

        if output.transferCategory == .privateAccount
            && !input.transferCart.sourceAccount.firstCurrency.isEmpty
            && bankAccount.firstCurrency.code != input.transferCart.sourceAccount.firstCurrency.code {
            startFetchLoading()
            validateValasCutOffTime()
            return
        }

        startSubmissionSucceed(identifier)
    }

    func setSelectedTransferCategory(_ category: TransferCategory) {
        repository.transferCategory = category
        output.transferCategory = category
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
