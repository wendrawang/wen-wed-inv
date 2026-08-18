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
        let useCase = createUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)

        trackForMemoryLeaks([sut, useCase])
    }

    // PERUBAHAN: test baru, menjaga aturan terpenting `TransferLandingFactory`.
    //
    // Closure `Routing` berakhir tersimpan di `useCase.callback`, dan ViewModel
    // menyimpan UseCase. Closure yang menangkap ViewModel karena itu menutup
    // lingkaran — dan bentuk salahnya menggoda, karena `viewModel` biasanya
    // sudah ada di scope pemanggil:
    //
    //     onSubmissionSucceed: { _ in self.route(viewModel) }   // salah
    //     onSubmissionSucceed: { viewModel in self.route(viewModel) }  // benar
    //
    // Test ini merah untuk bentuk yang pertama.
    func testFactoryBuiltViewModelIsReleased() {
        let factory = TransferLandingFactory(transferCart: TransferCart())

        let sut = factory.createViewModel(
            routing: TransferLandingFactory.Routing(
                onRequestNewRecipient: { _ in },
                onSubmissionSucceed: { _ in }
            )
        )

        trackForMemoryLeaks([sut, sut.useCase])
    }

    // MARK: - Membelah tahap: di mana lingkaran itu terbentuk

    // PERUBAHAN: dua test di bawah ini baru.
    //
    // `testRowActionsDoNotRetainViewModel` merah, sementara dua test di atas
    // hijau. Itu memberi tahu bahwa lingkaran terbentuk di suatu tempat antara
    // `setUseCase()` dan selesainya `loadData()` — tetapi tidak memberi tahu di
    // mana. Dua test ini membelah rentang itu, dan keduanya **tidak** bergantung
    // pada `RecipientService` yang di-stub, jadi hasilnya bisa dipercaya apa
    // adanya.
    //
    // Cara membaca hasilnya:
    //
    // | Yang merah | Lingkarannya ada di |
    // |---|---|
    // | `testInitStateDoesNotRetain…` | `initState()` — kandidat utama `activateDebounceInput()` pada `searchBarViewModel`, kalau langganannya menangkap `self` kuat |
    // | `testLoadDataDoesNotRetain…` saja | `loadData()` — kandidat utama `super.loadData()` di base pagination, lewat `infiniteScrollViewModel` |
    // | hanya `testRowActions…` | pemasangan aksi per baris, jadi di `createAccountHeadlineViewModel` |

    /// Memisahkan `initState()` dari `loadData()`.
    ///
    /// `initState()` memanggil `activateDebounceInput()`, dan debounce hampir
    /// selalu berarti langganan Combine. Kalau langganan itu menangkap `self`
    /// secara kuat sementara cancellable-nya disimpan di ViewModel, lingkarannya
    /// tertutup di situ — bukan di daftar.
    func testInitStateDoesNotRetainViewModel() {
        let useCase = createUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)
        sut.initState()

        trackForMemoryLeaks([sut, useCase])
    }

    /// Memisahkan `loadData()` dari pemasangan aksi per baris.
    ///
    /// Sengaja tanpa assertion apa pun tentang isi daftar. Kalau
    /// `RecipientService` belum di-stub, daftarnya kosong dan test ini tetap
    /// bermakna: `setupView()` dan `super.loadData()` sudah berjalan, dan
    /// keduanya cukup untuk membentuk lingkaran kalau ada.
    func testLoadDataDoesNotRetainViewModel() {
        let useCase = createUseCase()
        let sut = TransferLandingViewModel()

        sut.setUseCase(useCase)
        sut.loadData()
        drainMainQueue()

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
    ///
    /// Karena itu, baca dulu **pesan** kegagalannya sebelum mencari `weak` yang
    /// lupa. "Recipient list is empty" berarti stub-nya yang belum ada, bukan
    /// ada yang bocor — pakai `testLoadDataDoesNotRetainViewModel` di atas untuk
    /// pertanyaan kebocorannya, karena ia tidak butuh stub.
    func testRowActionsDoNotRetainViewModel() {
        let useCase = createUseCase()
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
        let useCase = createUseCase()
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

    private func createUseCase() -> TransferLandingUseCase {
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
