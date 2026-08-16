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
        callback.onStartFetchLoading()
        repository.bankCard = input.bankCard
        startFetchSucceed(identifier)
    }
}

extension DetailCardInfoScreenUseCase {

    /// Satu-satunya sumber baca untuk ViewModel.
    ///
    /// `input` adalah apa yang diminta, `repository` adalah apa yang sudah
    /// terselesaikan. Keduanya hanya bertemu di dalam `loadData()`. ViewModel
    /// yang membaca `input` akan tampak benar padahal melewati satu langkah,
    /// dan ViewModel yang membaca `repository` sebelum `loadData()` jalan akan
    /// menampilkan field kosong. Akses tunggal ini membuat pilihannya tidak
    /// ambigu dan salahnya sulit dilakukan tanpa sengaja.
    var bankCard: BankCard {
        repository.bankCard
    }

    class Input {
        var bankCard = BankCard(.unspecified)
    }

    class Repository {
        var bankCard = BankCard(.unspecified)
    }
}
