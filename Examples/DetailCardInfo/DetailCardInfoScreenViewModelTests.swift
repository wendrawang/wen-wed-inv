import XCTest

/// Contoh test yang menegakkan aturan lifecycle untuk satu layar.
/// Salin bentuk ini saat memigrasi layar lain.
final class DetailCardInfoScreenViewModelTests: XCTestCase {

    /// Menangkap retain cycle yang dibuat oleh `ScreenContentViewModel.init()`.
    ///
    /// Tidak ada persiapan sama sekali — hanya membuat objeknya. Kalau test ini
    /// merah, lingkarannya terbentuk di `init()` base class dan berlaku untuk
    /// **setiap layar** di aplikasi, bukan hanya layar ini. Lihat
    /// docs/BASE_VIEWMODEL_FINDINGS.md temuan 1.
    ///
    /// Jalankan ini lebih dulu daripada test lain di file ini.
    func testScreenViewModelIsReleasedAfterInit() {
        let sut = DetailCardInfoScreenViewModel()

        trackForMemoryLeaks(sut)
    }

    /// Menangkap retain cycle antara ViewModel dan UseCase.
    ///
    /// Test ini gagal kalau `setUseCase` kembali memakai referensi method
    /// (`onFetchSucceed = setupView`) alih-alih closure `[weak self]`, karena
    /// ViewModel menyimpan UseCase sementara UseCase menyimpan closure yang
    /// menahan ViewModel.
    func testViewModelAndUseCaseAreReleased() {
        let useCase = makeUseCase()
        let sut = DetailCardInfoScreenViewModel()

        sut.setUseCase(useCase)

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menangkap retain cycle lewat closure aksi salin nomor kartu.
    func testCardNumberActionDoesNotRetainViewModel() {
        let useCase = makeUseCase()
        let sut = DetailCardInfoScreenViewModel()

        sut.setUseCase(useCase)
        sut.loadData()
        drainMainQueue()

        XCTAssertFalse(
            sut.cardNumberViewModel.subtitles.isEmpty,
            "Aksi belum terpasang karena tampilan belum terisi."
        )

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menjaga perbaikan bug "CVV dan nomor kartu kosong".
    ///
    /// Yang diuji adalah urutannya: setelah `loadData()` dan antrean main
    /// selesai, field harus terisi. Kalau suatu saat ada yang memanggil
    /// `setupView()` sebelum repository terisi, atau `loadData()` hilang dari
    /// jalur pembangunan coordinator, test ini merah.
    func testFieldsArePopulatedAfterLoadData() {
        let bankCard = BankCard.stubbed()
        let useCase = makeUseCase(bankCard: bankCard)

        let sut = DetailCardInfoScreenViewModel()
        sut.configure(with: bankCard)
        sut.setUseCase(useCase)

        sut.loadData()
        drainMainQueue()

        XCTAssertFalse(
            sut.cardNumberViewModel.subtitles.isEmpty,
            "Nomor kartu masih kosong setelah loadData()."
        )
        XCTAssertFalse(
            sut.cvvViewModel.subtitle.isEmpty,
            "CVV masih kosong setelah loadData()."
        )

        trackForMemoryLeaks([sut, useCase])
    }

    // MARK: - Bantuan

    /// `renewIdentifier()` wajib — tanpanya `state` tetap `.inactive` dan
    /// `requestLoadData()` melewati pemuatan data. Di build Debug base UseCase
    /// akan berhenti dengan `assertionFailure`; di Release ia diam saja, dan
    /// itulah bentuk kegagalan yang dulu membuat layar berdiri kosong.
    private func makeUseCase(
        bankCard: BankCard = .stubbed()
    ) -> DetailCardInfoScreenUseCase {
        let useCase = DetailCardInfoScreenUseCase()

        useCase.renewIdentifier()
        useCase.input.bankCard = bankCard

        return useCase
    }

    /// Menunggu antrean main kosong.
    ///
    /// `startFetchSucceed(_:)` mengirim `onFetchSucceed` lewat
    /// `DispatchQueue.main.async`, jadi `setupView()` belum berjalan saat
    /// `loadData()` selesai. Karena antrean main bersifat FIFO, blok yang
    /// dimasukkan setelahnya dijamin berjalan paling akhir.
    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")

        DispatchQueue.main.async {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
