import Foundation

class DetailCardInfoScreenUseCase: UseCase, UseCaseProtocol {
    private(set) var repository = Repository()
    var input = Input()
    var callback = BaseCallback()

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    override init() {
        super.init()

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    override func flushData() {
        super.flushData()
        repository = Repository()
    }

    override func loadData() {
        super.loadData()

        // `startFetchLoading()`, bukan `callback.onStartFetchLoading()`.
        // Helper-nya membungkus pemanggilan dalam DispatchQueue.main.async;
        // memanggil callback langsung melewati jaminan itu dan menulis
        // `@Published` dari thread mana pun `loadData()` kebetulan berjalan.
        startFetchLoading()

        repository.bankCard = input.bankCard
        startFetchSucceed(identifier)
    }
}

extension DetailCardInfoScreenUseCase {

    class Input {
        var bankCard = BankCard(.unspecified)
    }

    class Repository {
        var bankCard = BankCard(.unspecified)
    }
}
