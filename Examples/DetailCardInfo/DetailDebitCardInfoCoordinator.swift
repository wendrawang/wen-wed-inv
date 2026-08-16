import SwiftUI

/// Coordinator versi perbaikan untuk layar Detail Debit Card Info.
///
/// Empat aturan yang membedakannya dari versi lama, dan keempatnya yang
/// menyembuhkan bug "CVV dan nomor kartu kadang kosong":
///
/// 1. Tidak ada stored property yang menyimpan ViewModel atau UseCase.
///    Struct `View` di-init ulang setiap kali body induk dievaluasi, jadi
///    `private let viewModel = ...` berarti objek baru pada setiap render.
/// 2. Semua objek dibangun **di dalam builder** `LazyNavigationLink`, yang
///    hanya jalan sekali saat layar di-push.
/// 3. Coordinator memanggil `loadData()`, **tidak pernah** `setupView()`.
///    Pengisian tampilan dijalankan oleh callback UseCase, satu jalur saja.
/// 4. Semua closure yang disimpan orang lain memakai `[weak self]` atau
///    hanya menangkap nilai, tidak pernah menangkap struct View.
struct DetailDebitCardInfoCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    @Binding var debitCard: BankCard

    var body: some View {
        LazyNavigationLink(
            tag: DetailDebitCardInfoCoordinator.named,
            selection: $selectionCoordinatorName
        ) {
            createDestination()
        }
    }

    // MARK: - Pembangunan layar

    /// Dipanggil sekali saat push. Aman melakukan konfigurasi di sini karena
    /// ViewModel-nya baru saja dibuat dan belum diamati view mana pun —
    /// berbeda dengan mengubahnya dari dalam `body`, yang merupakan mutasi
    /// state di tengah view update dan hasilnya tidak terdefinisi.
    private func createDestination() -> some View {
        let bankCard = debitCard
        let useCase = createUseCase(bankCard: bankCard)
        let viewModel = createViewModel(useCase: useCase, bankCard: bankCard)

        return Screen {
            DetailCardInfoScreen(viewModel: viewModel)
        }
    }

    private func createUseCase(
        bankCard: BankCard
    ) -> DetailCardInfoScreenUseCase {
        let useCase = DetailCardInfoScreenUseCase()

        // Sekali saja, pada objek yang memang baru. Versi lama memanggil ini
        // pada setiap evaluasi body, sehingga identifier bisa berganti saat
        // sebuah fetch masih berjalan dan hasilnya dibuang diam-diam.
        useCase.renewIdentifier()
        useCase.input.bankCard = bankCard

        return useCase
    }

    private func createViewModel(
        useCase: DetailCardInfoScreenUseCase,
        bankCard: BankCard
    ) -> DetailCardInfoScreenViewModel {
        let viewModel = DetailCardInfoScreenViewModel()

        // Menangkap Binding-nya saja, bukan seluruh struct coordinator.
        // Menulis `action: dismissScreenHandler` akan menyalin `self` beserta
        // semua Binding dan State-nya ke dalam ViewModel, dan salinan itu
        // adalah snapshot dari render saat closure dibuat.
        let sourceCoordinatorName = $sourceCoordinatorName

        viewModel.analytic = analytic(for: bankCard)
        viewModel.ignoreSafeAreaNavigationBar()
        viewModel.setupDismissScreenButton(
            action: { sourceCoordinatorName.wrappedValue = nil },
            iconNamed: R.image.iconSmallChevronLeft.name,
            iconColor: .white
        )

        viewModel.configure(with: bankCard)
        viewModel.setUseCase(useCase)

        // Mengisi repository sebelum view pertama dirender.
        //
        // Ini inti perbaikannya. ViewModel membaca `useCase.bankCard`, yang
        // isinya hanya terisi oleh `loadData()`. Versi lama memanggil
        // `setupView()` langsung dari body, jadi field dibaca saat repository
        // masih kosong dan layar bergantung pada render kedua untuk terisi —
        // render yang kadang tidak pernah datang.
        viewModel.loadData()

        return viewModel
    }

    private func analytic(for bankCard: BankCard) -> AnalyticEvent {
        var event = AnalyticManager.instance.analytics.visitDebitCardDetails

        event.parameters = [
            .type: bankCard.provider.rawValue,
            .title: bankCard.name
        ]

        return event
    }
}
