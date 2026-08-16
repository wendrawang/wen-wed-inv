import XCTest

extension XCTestCase {

    /// Menegaskan bahwa `instance` sudah dilepas saat test selesai.
    ///
    /// Ini adalah lapis penegakan yang sebenarnya. `LifecycleProbe` mencetak
    /// informasi yang harus dibaca manusia; helper ini **menggagalkan CI**,
    /// jadi retain cycle tidak bisa lolos review hanya karena tidak ada yang
    /// sempat membuka konsol.
    ///
    ///     func testViewModelDoesNotLeak() {
    ///         let useCase = LoginUsernameUseCase()
    ///         let sut = UsernameScreenViewModel()
    ///         sut.setUseCase(useCase)
    ///
    ///         trackForMemoryLeaks(sut)
    ///         trackForMemoryLeaks(useCase)
    ///     }
    ///
    /// Blok teardown berjalan setelah test method selesai dan setelah
    /// variabel lokalnya dilepas, sehingga `instance` seharusnya sudah nil
    /// kalau tidak ada yang menahannya.
    ///
    /// Catatan: jangan panggil ini pada objek yang memang sengaja hidup
    /// selamanya (singleton, container tingkat aplikasi) — helper ini untuk
    /// objek berumur layar seperti ViewModel, UseCase, dan Coordinator.
    func trackForMemoryLeaks(
        _ instance: AnyObject,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let typeName = String(describing: type(of: instance))

        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                """
                \(typeName) belum dilepas setelah test selesai. \
                Kemungkinan besar ada retain cycle — periksa closure yang \
                disimpan (callback, sink, Timer, observer) dan pastikan \
                memakai [weak self].
                """,
                file: file,
                line: line
            )
        }
    }

    /// Versi ringkas untuk beberapa objek sekaligus.
    func trackForMemoryLeaks(
        _ instances: [AnyObject],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for instance in instances {
            trackForMemoryLeaks(instance, file: file, line: line)
        }
    }
}

#if DEBUG
extension XCTestCase {

    /// Menegaskan tidak ada objek berprobe yang tersisa hidup.
    ///
    /// Berguna untuk test integrasi yang menjalankan satu flow dari awal
    /// sampai kembali ke root. Panggil `LifecycleTracker.shared.reset()`
    /// di `setUp` supaya hitungannya bersih.
    func assertNoTrackedObjectsAlive(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let live = LifecycleTracker.shared.liveTypes()

        XCTAssertTrue(
            live.isEmpty,
            """
            Masih ada objek terlacak yang hidup setelah flow selesai: \
            \(live.sorted { $0.key < $1.key }
                .map { "\($0.value)x \($0.key)" }
                .joined(separator: ", ")).
            """,
            file: file,
            line: line
        )
    }
}
#endif
