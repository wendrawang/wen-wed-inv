import SwiftUI

/// Coordinator Transfer Landing.
///
/// **Bentuknya sengaja dibiarkan persis seperti aslinya.** Satu-satunya
/// perubahan ada di deklarasi `viewModel`; sisanya — `navigationLinks`, `body`,
/// `createViewModel()`, `createUseCase()`, dan seluruh perutean — tidak
/// disentuh sama sekali.
///
/// Alasannya dua. Struktur navigasi di sini terikat pada
/// `.id(destinationCoordinatorName)`, yang ternyata bukan tambalan melainkan
/// bagian yang membuat push-nya bekerja — lihat catatan di bawah file. Dan
/// perbaikan yang benar-benar berdampak untuk layar ini semuanya ada di
/// ViewModel dan UseCase, bukan di sini.
struct TransferLandingCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var transferCart: TransferCart

    @State private var destinationCoordinatorName: String?
    @State private var useCase = TransferLandingUseCase()

    /// Satu-satunya perubahan di file ini: `private let` menjadi `@State`.
    ///
    /// Struct `View` di-init ulang setiap kali body induknya dievaluasi, jadi
    /// `private let viewModel = TransferLandingViewModel()` menghasilkan
    /// ViewModel baru pada setiap render — seluruh sub-ViewModel-nya kembali
    /// kosong dan harus dikonfigurasi ulang. `@State` menyimpannya di luar
    /// struct sehingga instance-nya bertahan.
    ///
    /// Bentuknya sama persis dengan `useCase` di baris atas, yang memang sudah
    /// `@State` sejak awal.
    @State private var viewModel = TransferLandingViewModel()

    private var navigationLinks: [String: TypeAliases.NavigationHandler] {[
        TransferTransactionAmountCoordinator.named: {
            AnyView(
                TransferTransactionAmountCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    recipientAccount: $useCase.output.recipientAccount,
                    recipientProfile: .constant(TransactionActorProfile()),
                    sourceAccount: $transferCart.sourceAccount,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod,
                    transferCategory: $useCase.output.transferCategory,
                    predefineTransferPurpose: .constant(Option()),
                    editTransferTarget: .constant(TransferTarget()),
                    additionalInfo: $useCase.output.additionalInfo,
                    transferMethods: $useCase.output.transferMethods,
                    thematic: useCase.output.thematic
                )
            )
        },

        TransferDebitAccountSelectionCoordinator.named: {
            AnyView(
                TransferDebitAccountSelectionCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    recipientAccount: $useCase.output.recipientAccount,
                    recipientProfile: .constant(TransactionActorProfile()),
                    transferCategory: $useCase.output.transferCategory,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod,
                    transferSpec: .constant(TransferSpec()),
                    predefineTransferPurpose: .constant(Option()),
                    backButtonAnalytic: .constant(
                        AnalyticManager.instance.analytics.hitBackOnSourceAccountPrivateTransfer
                    ),
                    isUsingValidateValasCutOffTime: .constant(true),
                    thematic: useCase.output.thematic
                )
            )
        },

        DomesticTransferNewRecipientCoordinator.named: {
            AnyView(
                DomesticTransferNewRecipientCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart
                )
            )
        },

        ForeignTransferNewRecipientCoordinator.named: {
            AnyView(
                ForeignTransferNewRecipientCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart
                )
            )
        },

        ProxyTransferNewRecipientCoordinator.named: {
            AnyView(
                ProxyTransferNewRecipientCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart
                )
            )
        },

        TransferCurrencySelectionCoordinator.named: {
            AnyView(
                TransferCurrencySelectionCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    recipientAccount: $useCase.output.recipientAccount,
                    recipientProfile: .constant(TransactionActorProfile()),
                    transferCategory: $useCase.output.transferCategory,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod,
                    predefineTransferPurpose: .constant(Option()),
                    isUsingValidateValasCutOffTime: .constant(true),
                    thematic: useCase.output.thematic
                )
            )
        },

        BankSummaryCoordinator.named: {
            AnyView(
                BankSummaryCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    bank: $useCase.output.bank,
                    transferCategory: $useCase.output.transferCategory,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod
                )
            )
        },

        TransferCountrySelectionCoordinator.named: {
            AnyView(
                TransferCountrySelectionCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    transferCategory: $useCase.output.transferCategory,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod
                )
            )
        },

        TelegraphicRecipientFormCoordinator.named: {
            AnyView(
                TelegraphicRecipientFormCoordinator(
                    selectionCoordinatorName: $destinationCoordinatorName,
                    sourceCoordinatorName: sourceCoordinatorName == nil
                        ? $selectionCoordinatorName.didSet { _ in
                            destinationCoordinatorName = nil
                        }
                        : $sourceCoordinatorName,
                    transferCart: $transferCart,
                    bank: $useCase.output.bank,
                    transferCategory: $useCase.output.transferCategory,
                    transferMethod: $useCase.output.predefineSelectedTransferMethod,
                    recipientAccount: $useCase.output.recipientAccount,
                    additionalInfo: $useCase.output.additionalInfo
                )
            )
        }
    ]}

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

    private func createViewModel() -> TransferLandingViewModel {
        if selectionCoordinatorName != TransferLandingCoordinator.named {
            viewModel.flushData()
            useCase.flushData()
            return TransferLandingViewModel()
        }

        viewModel.onCreateNavigationLinks = createNavigationLinks

        viewModel.navigationBarViewModel.title = transferCart.targets.isEmpty
            ? R.string.navigationTitle.transferRecipient.text
            : String(
                format: R.string.navigationTitle.transferRecipientMultiple.text,
                transferCart.targets.count.nextNumber.ordinalText
            )

        viewModel.newRecipientMenuItemViewModel.action = startNewRecipientCoordinator

        viewModel.newRecipientMenuItemViewModel.analytic = AnalyticManager
            .instance
            .analytics
            .hitTransferLandingNewRecipient

        viewModel.newRecipientMenuItemViewModel.analytic.parameters = [
            .categoryTitle: viewModel
                .selectedTransferCategory
                .rawValue
        ]

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

    private func startNewRecipientCoordinator() {
        destinationCoordinatorName = viewModel
            .selectedTransferCategory
            .newRecipientDestinationCoordinatorName
    }

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
        if transferCart.targets.isEmpty {
            destinationCoordinatorName = TransferDebitAccountSelectionCoordinator.named
            return
        }

        destinationCoordinatorName = TransferTransactionAmountCoordinator.named
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

    private func createNavigationLinks() -> AnyView {
        if let destination = destinationCoordinatorName,
           let navigationLink = navigationLinks[destination] {
            return navigationLink()
        }

        return DefaultValues.emptyAnyView
    }
}

// MARK: - Kenapa file ini nyaris tidak diubah
//
// Saya sempat mengganti struktur navigasinya — `LazyNavigationLink`, `.id()`
// dihapus, kamus `navigationLinks` dipindah ke sebuah tipe baru. Ketiganya
// dikembalikan.
//
// `.id(destinationCoordinatorName)` bukan tambalan. `createNavigationLinks()`
// hanya membangun tautan untuk tujuan yang cocok, jadi saat nilainya masih nil
// tidak ada satu pun tautan anak di pohon view. Ketika nilainya berubah, tautan
// anak muncul dengan selection-nya sudah sama dengan tag-nya — dan
// `NavigationView` di iOS 13-14 tidak melakukan push untuk tautan yang
// disisipkan dalam keadaan sudah terpilih. `.id()` membangun ulang subtree-nya
// sebagai identitas baru sehingga push-nya terjadi. Menghapusnya mematikan
// navigasi.
//
// `.id()` juga tidak bisa hidup bersama `LazyNavigationLink`: builder lazy
// hanya berjalan sekali lalu hasilnya disimpan, jadi nilai `.id()` beku pada
// pembacaan pertama.
//
// Kamus `navigationLinks` memang dibangun ulang setiap kali diakses — sembilan
// closure dan satu Dictionary per evaluasi body. Itu biaya nyata, tetapi kecil
// dibanding yang sudah diperbaiki di ViewModel, dan menggantinya berarti
// memperkenalkan bentuk yang tidak dipakai di halaman lain. Kalau kelak ingin
// dikejar, `switch` bisa menggantikannya tanpa mengubah perilaku — tetapi
// sebaiknya diputuskan sebagai konvensi tim, bukan diselipkan di satu layar.
