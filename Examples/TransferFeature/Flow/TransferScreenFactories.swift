import SwiftUI

/// Pembangunan layar tujuan, diserahkan aplikasi.
///
/// Coordinator flow tahu **urutan** dan **syarat** perpindahan; ia tidak tahu
/// cara membangun satu pun layar tujuan. Pemisahan itu yang membuat coordinator
/// bisa diuji tanpa SwiftUI, dan membuat migrasi bisa satu layar sekali jalan:
/// selama sebuah tujuan belum punya factory-nya sendiri, isinya boleh apa saja.
///
/// ## Cara mengisinya
///
/// Setiap closure di sini adalah versi `TransferLandingFactory` untuk layar yang
/// bersangkutan — bangun UseCase-nya, isi `input`-nya, bangun ViewModel-nya,
/// sambungkan, kembalikan layarnya. Nilai yang dibutuhkan dibaca dari
/// `useCase.output`, memakai ekspresi yang sama persis dengan yang sekarang ada
/// di `TransferLandingCoordinator`. Contoh untuk satu tujuan:
///
/// ```swift
/// createTransactionAmount: { useCase in
///     AnyView(
///         TransferTransactionAmountFactory(
///             transferCart: useCase.repository.transferCart,
///             recipientAccount: useCase.output.recipientAccount,
///             transferCategory: useCase.output.transferCategory,
///             transferMethods: useCase.output.transferMethods
///         )
///         .createScreen(routing: ...)
///     )
/// }
/// ```
///
/// ## Soal `AnyView`
///
/// `AnyView` di sini tidak sama dengan `AnyView` di dalam `body`. Closure ini
/// dipanggil **sekali per perpindahan**, bukan setiap evaluasi body, jadi
/// biayanya satu alokasi per layar yang dibuka. Yang mahal adalah `AnyView`
/// yang dievaluasi ulang puluhan kali per detik, dan itu justru yang hilang
/// bersama `onCreateNavigationLinks`.
struct TransferScreenFactories {

    var createNewRecipient: (TransferLandingUseCase, TransferCategory) -> AnyView
    var createTransactionAmount: (TransferLandingUseCase) -> AnyView
    var createDebitAccountSelection: (TransferLandingUseCase) -> AnyView
    var createCurrencySelection: (TransferLandingUseCase) -> AnyView
    var createCountrySelection: (TransferLandingUseCase) -> AnyView
    var createTelegraphicRecipientForm: (TransferLandingUseCase) -> AnyView
    var createBankSummary: (TransferLandingUseCase) -> AnyView
}

extension TransferScreenFactories {

    /// Layar untuk sebuah rute, atau `nil` kalau rutenya adalah landing —
    /// landing dibangun coordinator sendiri lewat `TransferLandingFactory`.
    ///
    /// Dipisah ke sini supaya `switch` yang panjang tidak menumpuk di
    /// coordinator, dan supaya menambah tujuan baru cukup menyentuh satu file.
    func createScreen(for route: TransferRoute) -> AnyView? {
        switch route {
        case .landing:
            return nil

        case .newRecipient(let useCase, let category):
            return createNewRecipient(useCase, category)

        case .transactionAmount(let useCase):
            return createTransactionAmount(useCase)

        case .debitAccountSelection(let useCase):
            return createDebitAccountSelection(useCase)

        case .currencySelection(let useCase):
            return createCurrencySelection(useCase)

        case .countrySelection(let useCase):
            return createCountrySelection(useCase)

        case .telegraphicRecipientForm(let useCase):
            return createTelegraphicRecipientForm(useCase)

        case .bankSummary(let useCase):
            return createBankSummary(useCase)
        }
    }
}
