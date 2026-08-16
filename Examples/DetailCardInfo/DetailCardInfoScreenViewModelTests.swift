import XCTest

/// Contoh test yang menegakkan aturan lifecycle untuk satu layar.
/// Salin bentuk ini saat memigrasi layar lain.
final class DetailCardInfoScreenViewModelTests: XCTestCase {

    /// Menangkap retain cycle antara ViewModel dan UseCase.
    ///
    /// Test ini gagal kalau `setUseCase` kembali memakai referensi method
    /// (`onFetchSucceed = setupView`) alih-alih closure `[weak self]`, karena
    /// ViewModel menyimpan UseCase sementara UseCase menyimpan closure yang
    /// menahan ViewModel.
    func testViewModelAndUseCaseAreReleased() {
        let useCase = DetailCardInfoScreenUseCase()
        let sut = DetailCardInfoScreenViewModel()

        sut.setUseCase(useCase)

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menangkap retain cycle lewat closure aksi salin nomor kartu.
    func testCardNumberActionDoesNotRetainViewModel() {
        let useCase = DetailCardInfoScreenUseCase()
        useCase.input.bankCard = BankCard.stubbed()

        let sut = DetailCardInfoScreenViewModel()
        sut.setUseCase(useCase)
        sut.loadData()

        // Aksi sudah terpasang di sini; kalau ia menahan ViewModel,
        // teardown akan gagal.
        XCTAssertNotNil(sut.cardNumberViewModel.action)

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menjaga perbaikan bug "CVV dan nomor kartu kosong".
    ///
    /// Yang diuji adalah urutannya: setelah `loadData()`, field harus sudah
    /// terisi tanpa perlu render kedua. Kalau suatu saat ada yang memanggil
    /// `setupView()` sebelum repository terisi, atau `loadData()` hilang dari
    /// jalur pembangunan coordinator, test ini merah.
    func testFieldsArePopulatedAfterLoadData() {
        let bankCard = BankCard.stubbed()

        let useCase = DetailCardInfoScreenUseCase()
        useCase.renewIdentifier()
        useCase.input.bankCard = bankCard

        let sut = DetailCardInfoScreenViewModel()
        sut.configure(with: bankCard)
        sut.setUseCase(useCase)

        sut.loadData()

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
}
