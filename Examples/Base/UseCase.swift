import Foundation

/// Base `UseCase` dengan dua perubahan yang berlaku untuk **seluruh** halaman.
///
/// Keduanya mengubah kegagalan senyap menjadi kegagalan yang terdengar. Tidak
/// ada perubahan perilaku di build Release — `assertionFailure` dikompilasi
/// habis — jadi ini aman dipasang lebih dulu sebelum halaman mana pun disentuh.
class UseCase {
    var identifier = UUID()
    var state: State = .inactive

    // MARK: - Perubahan 1: `state == .inactive` tidak boleh diam

    /// `state` hanya menjadi `.active` lewat `renewIdentifier()`. Kalau sebuah
    /// UseCase dipakai tanpa itu, `requestLoadData()` **tidak melakukan
    /// apa-apa dan tidak mengeluh** — layar berdiri kosong selamanya tanpa
    /// satu pun petunjuk di mana salahnya.
    ///
    /// Ini bukan kasus teoretis. `DetailCardInfoScreenViewModel` dan semua
    /// ViewModel sejenis punya `useCase` default yang `state`-nya `.inactive`.
    /// Setiap jalur yang mengirim ViewModel default ke layar — misalnya cabang
    /// yang mengembalikan `SomeViewModel()` saat coordinator belum aktif —
    /// menghasilkan layar yang tidak akan pernah memuat data.
    func requestLoadData() {
        if state == .inactive {
            assertionFailure(
                """
                requestLoadData() dipanggil pada \(type(of: self)) yang masih \
                .inactive. renewIdentifier() belum pernah dipanggil, jadi \
                pemuatan data dilewati diam-diam dan layar akan tetap kosong. \
                Pastikan coordinator memanggil renewIdentifier() saat UseCase \
                dibuat, dan ViewModel menerima UseCase itu lewat setUseCase().
                """
            )
            return
        }

        loadData()
    }

    func requestLoadData(
        pageNumber: Int,
        searchKeyword: String
    ) {
        if state == .inactive {
            assertionFailure(
                """
                requestLoadData(pageNumber:searchKeyword:) dipanggil pada \
                \(type(of: self)) yang masih .inactive.
                """
            )
            return
        }

        loadData(pageNumber: pageNumber, searchKeyword: searchKeyword)
    }

    func loadData() {
        return
    }

    func loadData(pageNumber: Int, searchKeyword: String) {
        return
    }

    func flushData() {
        return
    }

    func renewIdentifier() {
        identifier = UUID()
        state = .active
    }

    func reloadData() {
        flushData()
        loadData()
    }
}

extension UseCase {
    enum State {
        case active
        case inactive
    }
}

extension UseCase {
    class BaseCallback {
        var onStartSubmissionLoading: TypeAliases.VoidHandler = { return }
        var onStopSubmissionLoading: TypeAliases.VoidHandler = { return }
        var onSubmissionSucceed: TypeAliases.VoidHandler = { return }
        var onSubmissionFailed: TypeAliases.ResponseErrorHandler = { _ in }
        var onStartFetchLoading: TypeAliases.VoidHandler = { return }
        var onStopFetchLoading: TypeAliases.VoidHandler = { return }
        var onFetchSucceed: TypeAliases.VoidHandler = { return }
        var onFetchFailed: TypeAliases.ResponseErrorHandler = { _ in }
        var onFlushSucceed: TypeAliases.VoidHandler = { return }
        var onStartCoordinatorFromErrorMessage: TypeAliases.StringHandler?
    }
}

// Perubahan 2 tidak ada di file ini karena bukan perubahan kode base, tapi
// aturan pemakaian: UseCase tidak boleh menyentuh `callback` secara langsung,
// selalu lewat helper di `UseCaseProtocol`. Alasannya ada di
// docs/SCREEN_PATTERN.md, aturan 10.
