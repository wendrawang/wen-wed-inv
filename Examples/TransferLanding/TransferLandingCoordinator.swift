import SwiftUI

/// Coordinator Transfer Landing.
///
/// **Struktur navigasinya sengaja dibiarkan seperti versi lama.** Berbeda
/// dengan `DetailDebitCardInfoCoordinator`, layar ini tidak dipindah ke
/// `LazyNavigationLink`. Alasannya ada di bagian bawah file ini — singkatnya,
/// `.id(destinationCoordinatorName)` di sini **bukan tambalan**, melainkan
/// bagian yang membuat navigasinya bekerja, dan ia tidak bisa hidup
/// berdampingan dengan cache milik `LazyNavigationLink`.
///
/// Yang diperbaiki hanya bagian yang tidak menyentuh struktur navigasi:
///
/// 1. `viewModel` dipindah dari `private let` ke `@State`, supaya tidak
///    dialokasikan ulang pada setiap init struct.
/// 2. Kamus sembilan closure diganti `switch` di `NavigationLinkFactory` —
///    perilakunya identik, hanya tanpa alokasi kamus dan sembilan konteks
///    closure pada setiap evaluasi body.
/// 3. Analitik tombol recipient baru dirakit di ViewModel saat aksinya
///    dijalankan, bukan di sini saat ViewModel dibangun.
struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    @State private var destinationCoordinatorName: String?
    @State private var useCase = TransferLandingUseCase()

    /// `@State`, bukan `private let`.
    ///
    /// Struct `View` di-init ulang setiap kali body induknya dievaluasi, jadi
    /// `private let viewModel = TransferLandingViewModel()` berarti ViewModel
    /// baru pada setiap render. `@State` menyimpannya di luar struct sehingga
    /// instance-nya bertahan.
    ///
    /// Ini bukan bentuk terbaik — ekspresi defaultnya tetap dievaluasi lalu
    /// dibuang setiap init — tetapi ia bentuk terbaik yang bisa dipakai tanpa
    /// mengubah struktur navigasi, dan iOS 13 tidak punya `@StateObject`.
    @State private var viewModel = TransferLandingViewModel()

    var predefineTransferCategory: TransferCategory = .unspecified

    var body: some View {
        NavigationLink(
            destination: ZStack {
                Screen {
                    TransferLandingScreen(
                        viewModel: createViewModel()
                    )
                }
                .id(destinationCoordinatorName)
            },
            tag: TransferLandingCoordinator.named,
            selection: $selectionCoordinatorName
        ) {
            EmptyView()
        }
        .invisible()
    }

    // MARK: - Pembangunan layar

    private func createViewModel() -> TransferLandingViewModel {
        if selectionCoordinatorName != TransferLandingCoordinator.named {
            viewModel.flushData()
            useCase.flushData()
            return TransferLandingViewModel()
        }

        viewModel.onCreateNavigationLinks = createNavigationLinks

        viewModel.navigationBarViewModel.title = navigationTitle()

        // Coordinator hanya menentukan tujuan; kategori yang sedang terpilih
        // datang dari ViewModel sebagai argumen.
        //
        // Versi lama merakit parameter analitiknya di sini, pada saat ViewModel
        // dibangun — yaitu sebelum `loadData()` pernah berjalan — sehingga
        // kategori yang terkirim selalu `.unspecified`. Sekarang perakitannya
        // ada di ViewModel, di titik aksinya benar-benar dijalankan.
        viewModel.onStartNewRecipient = { transferCategory in
            destinationCoordinatorName = transferCategory
                .newRecipientDestinationCoordinatorName
        }

        viewModel.setUseCase(createUseCase())

        return viewModel
    }

    private func createUseCase() -> TransferLandingUseCase {
        useCase.renewIdentifier()
        useCase.input.transferCart = transferCart
        useCase.input.transferCategory = predefineTransferCategory
        useCase.callback.onSubmissionSucceed = startDestinationCoordinator

        return useCase
    }

    private func navigationTitle() -> String {
        guard !transferCart.targets.isEmpty else {
            return R.string.navigationTitle.transferRecipient.text
        }

        return String(
            format: R.string.navigationTitle.transferRecipientMultiple.text,
            transferCart.targets.count.nextNumber.ordinalText
        )
    }

    private func createNavigationLinks() -> AnyView {
        NavigationLinkFactory(
            selectionCoordinatorName: $selectionCoordinatorName,
            sourceCoordinatorName: $sourceCoordinatorName,
            destinationCoordinatorName: $destinationCoordinatorName,
            transferCart: $transferCart,
            useCase: useCase
        )
        .make()
    }

    // MARK: - Perutean

    private func startDestinationCoordinator() {
        if useCase.output.transferCategory == .privateAccount {
            startPrivateAccountJourney()
            return
        }

        if useCase.output.transferCategory == .valas {
            startValasJourney()
            return
        }

        destinationCoordinatorName = TransferTransactionAmountCoordinator.named
    }

    private func startPrivateAccountJourney() {
        destinationCoordinatorName = transferCart.targets.isEmpty
            ? TransferDebitAccountSelectionCoordinator.named
            : TransferTransactionAmountCoordinator.named
    }

    private func startValasJourney() {
        if !useCase.output.recipientAccount.bank.code.isEmpty {
            destinationCoordinatorName = TransferCurrencySelectionCoordinator.named
            return
        }

        if useCase.output.bank.code.isEmpty {
            destinationCoordinatorName = TransferCountrySelectionCoordinator.named
            return
        }

        if useCase.output.recipientAccount.accountName.isEmpty {
            destinationCoordinatorName = TelegraphicRecipientFormCoordinator.named
            return
        }

        destinationCoordinatorName = BankSummaryCoordinator.named
    }
}

// MARK: - Kenapa `.id()` tidak dihapus
//
// Saya sempat menghapusnya karena mengira ia tambalan untuk `AnyView` yang
// menghapus structural identity. Itu keliru, dan menghapusnya membuat navigasi
// ke layar berikutnya berhenti bekerja sama sekali.
//
// Mekanismenya begini. `createNavigationLinks()` hanya membangun tautan untuk
// tujuan yang cocok dengan `destinationCoordinatorName`, jadi saat nilainya
// masih nil tidak ada satu pun tautan anak di dalam pohon view. Ketika pengguna
// menekan sesuatu dan nilainya berubah, tautan anak baru **muncul dengan
// selection-nya sudah sama dengan tag-nya**. `NavigationView` di iOS 13–14
// tidak melakukan push untuk tautan yang disisipkan dalam keadaan sudah
// terpilih — ia perlu melihat perpindahan dari tidak-terpilih ke terpilih.
//
// `.id(destinationCoordinatorName)` membuat SwiftUI membangun ulang subtree-nya
// sebagai identitas baru, sehingga tautan anak itu terpasang di pohon yang
// benar-benar baru dan push-nya terjadi. Mahal, tetapi memang itu yang
// menggerakkan navigasinya.
//
// Dan `.id()` tidak bisa dipakai bersama `LazyNavigationLink`: builder-nya
// hanya berjalan sekali lalu hasilnya disimpan, jadi nilai `.id()` akan beku
// pada pembacaan pertama — yaitu nil — dan tidak pernah berubah lagi.
//
// Jadi keduanya satu paket. Melepas layar ini dari `.id()` berarti mengganti
// cara tautan anak disisipkan — misalnya menyisipkan tautannya lebih dulu lalu
// menyalakan selection-nya pada putaran runloop berikutnya. Itu perubahan yang
// harus dikerjakan sambil menjalankan aplikasinya, bukan ditebak dari kode.
