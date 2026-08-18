import SwiftUI

/// Pembangunan layar Transfer Landing, dipisahkan dari navigasinya.
///
/// Dibuat karena satu layar sebentar lagi punya **dua** pemanggil:
/// `TransferLandingCoordinator` yang berbasis `NavigationView`, dan coordinator
/// flow yang berbasis `UINavigationController`. Tanpa pemisahan ini, keduanya
/// akan menyimpan salinan logika pembangunan yang sama, dan dua salinan itu
/// menyimpang dalam hitungan minggu — biasanya diam-diam, lewat satu analytic
/// atau satu `input` yang lupa ikut diubah.
///
/// Pembagiannya satu garis: **apa pun yang tidak menyebut tujuan, ada di sini.**
/// UseCase beserta `input`-nya, judul, analytic, dan penyambungan ViewModel ke
/// UseCase. Yang menyebut tujuan diserahkan pemanggil lewat `Routing`.
///
/// ## Aturan yang harus dipatuhi closure `Routing`
///
/// **Jangan menangkap ViewModel-nya.** Ia datang sebagai parameter justru
/// supaya tidak perlu ditangkap. Closure `Routing` berakhir tersimpan di
/// `useCase.callback`, dan UseCase disimpan ViewModel — jadi closure yang
/// menangkap ViewModel menutup lingkaran, persis kelas kebocoran yang sudah
/// kita bersihkan di layar ini.
///
/// Kalau pemanggilnya sebuah class — coordinator flow UIKit nanti — closure-nya
/// tetap perlu `[weak self]` untuk dirinya sendiri.
struct TransferLandingFactory {

    /// Keputusan tujuan, milik pemanggil.
    ///
    /// Keduanya wajib. Tidak ada nilai default, supaya tidak ada jalur yang
    /// menghasilkan layar yang tampil normal tetapi tidak bisa ke mana-mana —
    /// kegagalan senyap yang paling mahal dilacak.
    struct Routing {

        /// Pengguna menekan "penerima baru". Kategorinya dibaca dari
        /// `viewModel.selectedTransferCategory`.
        var onRequestNewRecipient: (TransferLandingViewModel) -> Void

        /// Penerima sudah dipilih dan inquiry berhasil. Hasilnya dibaca dari
        /// `viewModel.useCase.output`.
        var onSubmissionSucceed: (TransferLandingViewModel) -> Void

        /// Pengguna menekan tombol back.
        ///
        /// Wajib diisi karena artinya **berbeda di kedua dunia**, dan itu tidak
        /// bisa disimpulkan dari dalam sini. Di `NavigationView`, layar ini
        /// punya induk di tumpukan yang sama, jadi back berarti mundur. Di flow
        /// UIKit, layar ini adalah layar pertama tumpukan modal, jadi back
        /// berarti menutup seluruh flow — `goBackOrFinish()`.
        var onRequestBack: (TransferLandingViewModel) -> Void
    }

    private let transferCart: TransferCart
    private let predefineTransferCategory: TransferCategory

    init(
        transferCart: TransferCart,
        predefineTransferCategory: TransferCategory = .unspecified
    ) {
        self.transferCart = transferCart
        self.predefineTransferCategory = predefineTransferCategory
    }
}

// MARK: - Pembangunan

extension TransferLandingFactory {

    /// Layar lengkap beserta pembungkus `Screen`-nya.
    ///
    /// Ini yang dipakai kedua dunia navigasi: `NavigationView` menaruhnya di
    /// dalam `LazyNavigationLink`, `UINavigationController` mendorongnya lewat
    /// `FlowNavigator.push`.
    func createScreen(routing: Routing) -> some View {
        Screen {
            TransferLandingScreen(viewModel: createViewModel(routing: routing))
        }
    }

    /// ViewModel yang sudah lengkap — termasuk UseCase-nya, yang bisa dibaca
    /// lagi lewat `viewModel.useCase` kalau pemanggil membutuhkannya.
    func createViewModel(routing: Routing) -> TransferLandingViewModel {
        let useCase = createUseCase()
        let viewModel = TransferLandingViewModel()

        viewModel.navigationBarViewModel.title = navigationTitle()
        viewModel.newRecipientMenuItemViewModel.analytic = AnalyticManager
            .instance
            .analytics
            .hitTransferLandingNewRecipient

        setupNewRecipientAction(on: viewModel, routing: routing)
        setupSubmissionRouting(on: useCase, viewModel: viewModel, routing: routing)
        setupBackAction(on: viewModel, routing: routing)

        viewModel.setUseCase(useCase)

        return viewModel
    }

    private func createUseCase() -> TransferLandingUseCase {
        let useCase = TransferLandingUseCase()

        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory

        return useCase
    }

    private func navigationTitle() -> String {
        if transferCart.targets.isEmpty {
            return R.string.navigationTitle.transferRecipient.text
        }

        return String(
            format: R.string.navigationTitle.transferRecipientMultiple.text,
            transferCart.targets.count.nextNumber.ordinalText
        )
    }
}

// MARK: - Penyambungan ke Routing

extension TransferLandingFactory {

    /// Analytic-nya urusan factory, tujuannya urusan pemanggil.
    ///
    /// Parameter analytic sengaja diisi di dalam aksinya, bukan saat ViewModel
    /// dibangun: `selectedTransferCategory` baru punya nilai yang benar setelah
    /// pengguna memilih kategori.
    private func setupNewRecipientAction(
        on viewModel: TransferLandingViewModel,
        routing: Routing
    ) {
        viewModel.newRecipientMenuItemViewModel.action = { [weak viewModel] in
            guard let viewModel = viewModel else { return }

            viewModel.newRecipientMenuItemViewModel.analytic.parameters = [
                .categoryTitle: viewModel.selectedTransferCategory.rawValue
            ]

            routing.onRequestNewRecipient(viewModel)
        }
    }

    /// ⚠️ **Satu baris di sini perlu Anda sesuaikan.**
    ///
    /// Saya belum pernah melihat isi `NavigationBarViewModel`, jadi nama
    /// property aksi back-nya (`onTapBackButton` di bawah) adalah tebakan.
    /// Ganti dengan nama yang sebenarnya — yang penting aksinya memanggil
    /// `routing.onRequestBack`, bukan menutup layar sendiri.
    ///
    /// Kalau di proyek Anda tombol back ditangani `Screen` lewat
    /// `@Environment(\.presentationMode)`, itu **harus** diganti untuk layar di
    /// dalam flow UIKit: `presentationMode.dismiss()` di dalam
    /// `UIHostingController` yang di-push tidak mem-pop tumpukannya.
    private func setupBackAction(
        on viewModel: TransferLandingViewModel,
        routing: Routing
    ) {
        viewModel.navigationBarViewModel.onTapBackButton = { [weak viewModel] in
            guard let viewModel = viewModel else { return }

            routing.onRequestBack(viewModel)
        }
    }

    /// Dipasang pada UseCase, bukan ViewModel, karena inilah callback yang
    /// menyala saat inquiry selesai.
    ///
    /// `[weak viewModel]` wajib: closure ini tersimpan di UseCase, dan
    /// ViewModel menyimpan UseCase.
    private func setupSubmissionRouting(
        on useCase: TransferLandingUseCase,
        viewModel: TransferLandingViewModel,
        routing: Routing
    ) {
        useCase.callback.onSubmissionSucceed = { [weak viewModel] in
            guard let viewModel = viewModel else { return }

            routing.onSubmissionSucceed(viewModel)
        }
    }
}
