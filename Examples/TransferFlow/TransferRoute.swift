import Foundation

/// Seluruh tujuan di dalam flow transfer, sebagai satu daftar tertutup.
///
/// Menggantikan `destinationCoordinatorName` yang berupa `String`. Bedanya
/// bukan soal selera: dengan enum, tujuan yang salah ketik tidak bisa
/// dikompilasi, dan setiap tujuan membawa persis data yang dibutuhkannya.
///
/// ## Kenapa membawa UseCase, bukan nilai-nilai lepas
///
/// Semua tujuan setelah landing membaca hasil inquiry dari `useCase.output` —
/// `recipientAccount`, `bank`, `transferCategory`, `transferMethods`, dan
/// seterusnya. Membawa UseCase-nya berarti pembangunan tiap tujuan bisa memakai
/// ekspresi yang **sama persis** dengan versi `NavigationView` hari ini, jadi
/// tidak ada logika lama yang tersenggol saat dipindah.
///
/// Konsekuensinya rute menahan UseCase secara kuat. Itu disengaja dan
/// berbatas: rute hidup selama flow-nya tampil, lalu `AppRouter`
/// mengosongkannya saat flow ditutup.
enum TransferRoute {

    /// Layar daftar penerima. Titik masuk yang paling umum.
    case landing(transferCart: TransferCart, category: TransferCategory)

    /// Tambah penerima baru. Layar sebenarnya berbeda per kategori — domestik,
    /// valas, atau proxy — dan pemilihannya ada di factory, memakai pemetaan
    /// yang sudah ada di aplikasi.
    case newRecipient(useCase: TransferLandingUseCase, category: TransferCategory)

    case transactionAmount(useCase: TransferLandingUseCase)
    case debitAccountSelection(useCase: TransferLandingUseCase)
    case currencySelection(useCase: TransferLandingUseCase)
    case countrySelection(useCase: TransferLandingUseCase)
    case telegraphicRecipientForm(useCase: TransferLandingUseCase)
    case bankSummary(useCase: TransferLandingUseCase)
}

/// Yang bisa dimintai perpindahan oleh sebuah layar.
///
/// Layar dan ViewModel tidak pernah menyebut `UINavigationController`,
/// `NavigationLink`, atau nama layar tujuan. Mereka hanya menyebut rute.
///
/// `AnyObject` supaya bisa dipegang `weak` — dan memang harus, karena
/// coordinator-lah yang memiliki layar, bukan sebaliknya.
protocol TransferRouting: AnyObject {

    /// Maju ke satu tujuan.
    func start(_ route: TransferRoute)

    /// Mundur satu layar.
    func goBack()

    /// Arti tombol back yang sebenarnya untuk sebuah layar di dalam flow.
    ///
    /// Di layar pertama flow, back berarti **menutup flow** dan kembali ke
    /// dunia SwiftUI; di layar mana pun setelahnya, back berarti mundur satu
    /// langkah. Perbedaan ini tidak pernah muncul di `NavigationView`, karena di
    /// sana layar pertama sebuah flow tetap punya induk di tumpukan yang sama.
    ///
    /// Ini yang harus dipasang ke tombol back layar, bukan `goBack()`.
    func goBackOrFinish()

    /// Mundur ke daftar penerima, berapa pun langkah yang sudah dilalui.
    func goBackToLanding()

    /// Menutup seluruh flow dan kembali ke dunia SwiftUI.
    func finishFlow()
}

// Pendaftarannya ke router global ada di `TransferFlowMount.swift`, supaya file
// ini tetap murni daftar tujuan tanpa tahu apa pun soal presentasi.
