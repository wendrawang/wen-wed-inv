import XCTest

/// Contoh test yang menegakkan aturan lifecycle untuk satu layar.
/// Salin bentuk ini saat memigrasi layar lain.
///
/// Dua test pertama berjalan tanpa persiapan data apa pun — keduanya menguji
/// lifetime, bukan isi. Hanya test ketiga yang butuh `BankCard` terisi, dan
/// stub-nya ada di bawah file ini untuk Anda sesuaikan.
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
    ///
    /// Isi kartunya tidak relevan di sini, jadi `input.bankCard` dibiarkan pada
    /// nilai defaultnya — yang diuji jalur closure-nya, bukan datanya.
    func testViewModelAndUseCaseAreReleased() {
        let useCase = DetailCardInfoScreenUseCase()
        useCase.renewIdentifier()

        let sut = DetailCardInfoScreenViewModel()
        sut.setUseCase(useCase)
        sut.loadData()
        drainMainQueue()

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menjaga perbaikan bug "CVV dan nomor kartu kosong".
    ///
    /// Yang diuji adalah urutannya: setelah `loadData()` dan antrean main
    /// selesai, field harus terisi. Kalau suatu saat ada yang memanggil
    /// `setupView()` sebelum repository terisi, atau `renewIdentifier()` hilang
    /// dari jalur pembangunan coordinator sehingga `requestLoadData()` dilewati
    /// diam-diam, test ini merah.
    func testFieldsArePopulatedAfterLoadData() {
        let bankCard = BankCard.stubbedForCardInfoTests()

        let useCase = DetailCardInfoScreenUseCase()
        useCase.renewIdentifier()
        useCase.input.bankCard = bankCard

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

// MARK: - Stub

private extension BankCard {

    /// **Sesuaikan dengan inisialiser `BankCard` di proyek Anda.**
    ///
    /// Bentuk di bawah ini adalah tebakan berdasarkan pemakaian
    /// `BankCard(.unspecified)` di `DetailCardInfoScreenUseCase`, jadi hampir
    /// pasti perlu disunting.
    ///
    /// Yang wajib dipenuhi hanya dua hal, karena hanya itu yang diperiksa:
    /// `number` tidak kosong, dan `cvv` tidak kosong. Sisanya boleh default —
    /// kalau `expiration` kosong, `makeCardExpiredViewModel` akan jatuh ke
    /// `DefaultValues.emptyDate` dan itu tidak mengganggu test ini.
    static func stubbedForCardInfoTests() -> BankCard {
        var bankCard = BankCard(.debitCard)

        bankCard.number = "4111111111111111"
        bankCard.cvv = "123"

        return bankCard
    }
}
