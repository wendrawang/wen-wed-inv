import XCTest

/// Test untuk layar panjang berlist. Bentuknya sama dengan
/// `DetailCardInfoScreenViewModelTests`, dengan dua tambahan yang khas layar
/// seperti ini: lingkaran yang jumlahnya mengikuti panjang daftar, dan
/// penerbitan yang jumlahnya mengikuti jumlah baris.
///
/// **Dua test pertama berjalan apa adanya.** Dua test terakhir memanggil
/// `loadData()`, yang berujung pada `RecipientService` — jadi keduanya butuh
/// service itu di-stub lebih dulu supaya mengembalikan satu halaman kontak
/// tanpa menyentuh jaringan. Tanpa stub, keduanya akan menggantung sampai
/// timeout atau lolos tanpa menguji apa pun.
///
/// Kalau proyek Anda belum punya jalur untuk men-stub `RecipientService`,
/// hapus dulu dua test terakhir dan pasang kembali setelah jalurnya ada. Dua
/// test pertama sudah menutup delapan lingkaran di `setUseCase`, yang
/// merupakan bagian terbesar dari perbaikan ini.
final class TransferLandingViewModelTests: XCTestCase {

    /// Menangkap lingkaran yang terbentuk saat objeknya baru dibuat.
    func testViewModelIsReleasedAfterInit() {
        let sut = TransferLandingViewModel()

        trackForMemoryLeaks(sut)
    }

    /// Menangkap delapan lingkaran di `setUseCase`.
    ///
    /// Test ini merah kalau salah satu callback kembali dipasang sebagai
    /// referensi method (`onFetchSucceed = setupRecipientList`), karena
    /// ViewModel menyimpan UseCase sementara UseCase menyimpan closure yang
    /// menahan ViewModel.
    func testViewModelAndUseCaseAreReleased() {
        let useCase = makeUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menangkap lingkaran yang jumlahnya mengikuti panjang daftar.
    ///
    /// Setiap baris menyimpan dua closure — aksi favorit dan aksi pilih — di
    /// objek yang kemudian disimpan ViewModel. Tanpa `[weak self]`, daftar
    /// seratus kontak berarti dua ratus lingkaran, dan jumlahnya tumbuh
    /// mengikuti data pengguna.
    ///
    /// **Butuh `RecipientService` di-stub.** Assertion pertama ada justru
    /// untuk mencegah test ini hijau palsu: daftar kosong berarti aksinya tidak
    /// pernah terpasang, sehingga tidak ada yang diuji.
    func testRowActionsDoNotRetainViewModel() {
        let useCase = makeUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)
        sut.loadData()
        drainMainQueue()

        XCTAssertFalse(
            sut.accountHeadlineViewModels.isEmpty,
            "Recipient list is empty, so the row actions were never wired up."
        )

        trackForMemoryLeaks([sut, useCase])
    }

    /// Menjaga perbaikan "satu penerbitan untuk seluruh daftar".
    ///
    /// Menghitung berapa kali `objectWillChange` menyala selama daftar diisi.
    /// Versi lama menulis langsung ke property `@Published` di dalam loop,
    /// sehingga jumlahnya mengikuti jumlah kontak. Versi sekarang membangun ke
    /// array lokal dan menerbitkan sekali.
    ///
    /// Ambang tiga dipilih longgar dengan sengaja — yang dijaga adalah
    /// jumlahnya tidak lagi **tumbuh mengikuti jumlah baris**, bukan angka
    /// pastinya, karena `loadData()` juga menyentuh property lain.
    ///
    /// **Butuh `RecipientService` di-stub**, dan stub-nya sebaiknya
    /// mengembalikan cukup banyak kontak — dua puluh atau lebih. Dengan
    /// segelintir baris, versi lama pun bisa lolos ambang ini.
    func testPopulatingListPublishesOnlyOnce() {
        let useCase = makeUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)

        var publishCount = 0
        let cancellable = sut.objectWillChange.sink { _ in
            publishCount += 1
        }

        sut.loadData()
        drainMainQueue()

        cancellable.cancel()

        XCTAssertLessThanOrEqual(
            publishCount,
            3,
            """
            Populating the recipient list published \(publishCount) times. \
            Building the array in place republishes once per row — build a \
            local array and assign it once instead.
            """
        )

        trackForMemoryLeaks([sut, useCase])
    }

    // MARK: - Bantuan

    private func makeUseCase() -> TransferLandingUseCase {
        let useCase = TransferLandingUseCase()

        useCase.renewIdentifier()
        useCase.input.transferCart = TransferCart()

        return useCase
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")

        DispatchQueue.main.async {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
