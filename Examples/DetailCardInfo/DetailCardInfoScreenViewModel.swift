import Foundation
import SwiftUI

class DetailCardInfoScreenViewModel: ScreenContentViewModel {
    @Published private(set) var headerBankCardViewModel = HeaderBankCardViewModel()
    @Published private(set) var cardNumberViewModel = MenuItemViewModel()
    @Published private(set) var cardExpiredViewModel = DescriptionVerticalViewModel()
    @Published private(set) var cvvViewModel = DescriptionVerticalViewModel()
    @Published private(set) var phoneNumberViewModel = DescriptionVerticalViewModel()
    @Published private(set) var tipsViewModel = TipsViewModel()

    private(set) var bankCardType: BankCardType = .unspecified
    /// `lazy` supaya nilai defaultnya tidak pernah benar-benar dibuat.
    ///
    /// Tanpa `lazy`, ekspresi default dievaluasi saat ViewModel dibuat, lalu
    /// langsung dibuang oleh `setUseCase(_:)` — terlihat jelas di log
    /// lifecycle sebagai satu pasang INIT/DEINIT yang tidak ada gunanya.
    /// Karena `setUseCase(_:)` **menulis** property ini sebelum ada yang
    /// membacanya, inisialiser lazy-nya tidak pernah dijalankan sama sekali.
    ///
    /// Perlu diingat `lazy var` tidak aman diakses dari banyak thread
    /// sekaligus sebelum terisi. Di sini aman karena ViewModel hanya disentuh
    /// dari main thread.
    private(set) lazy var useCase = DetailCardInfoScreenUseCase()

    /// Membuat `DateFormatter` termasuk operasi paling mahal di Foundation,
    /// dan pengisian tampilan bisa berjalan berkali-kali.
    ///
    /// `static` dipilih karena isinya konstan — tidak ada bagian formatter ini
    /// yang bergantung pada instance ViewModel. Property instance biasa
    /// sebenarnya sudah cukup untuk soal biaya; `static` sekadar menghindari
    /// duplikasi yang tidak ada gunanya.
    ///
    /// Syaratnya dua, dan keduanya terpenuhi di sini. Formatter ini tidak
    /// boleh diubah setelah dikonfigurasi — `DateFormatter` aman dipakai
    /// lintas thread selama hanya dibaca. Dan format ini harus format tetap,
    /// bukan teks yang mengikuti bahasa pengguna, karena objek yang hidup
    /// seumur aplikasi akan mengunci locale-nya pada saat pertama dibuat dan
    /// tidak ikut berubah kalau bahasa diganti dari dalam app.
    ///
    /// Untuk format yang harus mengikuti bahasa pengguna, pakai property
    /// instance biasa supaya ia dibangun ulang setiap layar dibuka.
    private static let monthAndYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormats.monthAndYear

        // Mengunci ke locale POSIX supaya format tetap ini tidak terpengaruh
        // setelan pengguna. Tanpa ini, perangkat dengan kalender non-Gregorian
        // akan menampilkan tahun yang berbeda untuk masa berlaku kartu yang
        // sama.
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter
    }()

    #if DEBUG
    private var lifecycleProbe: LifecycleProbe?
    #endif

    override init() {
        super.init()

        navigationBarViewModel.isSecureContent = true
        tipsViewModel = createTipsViewModel()

        #if DEBUG
        lifecycleProbe = LifecycleProbe(self)
        #endif
    }

    // MARK: - Konfigurasi

    /// Bagian tampilan yang datang langsung dari kartu, bukan dari hasil
    /// `loadData()`. Dipanggil coordinator sekali saat layar dibangun.
    func configure(with bankCard: BankCard) {
        bankCardType = bankCard.type
        headerBankCardViewModel = createHeaderBankCardViewModel(bankCard)
    }

    func setUseCase(_ useCase: DetailCardInfoScreenUseCase) {
        // `[weak self]` wajib di ketiganya. Menulis `onFetchSucceed = setupView`
        // menangkap self secara kuat, dan karena ViewModel menyimpan UseCase
        // sementara UseCase menyimpan closure ini, keduanya saling menahan dan
        // tidak akan pernah dilepas.
        useCase.callback.onStartFetchLoading = { [weak self] in
            self?.startLoading()
        }

        useCase.callback.onStopFetchLoading = { [weak self] in
            self?.stopLoading()
        }

        useCase.callback.onFetchSucceed = { [weak self] in
            self?.setupView()
        }

        self.useCase = useCase
    }

    // MARK: - Siklus data

    override func loadData() {
        super.loadData()
        useCase.requestLoadData()
    }

    override func flushData() {
        super.flushData()
        useCase.flushData()
    }

    /// Sengaja `private`.
    ///
    /// Pengisian tampilan hanya boleh dipicu oleh callback UseCase, supaya
    /// selalu berjalan setelah repository terisi. Versi lama memanggil ini
    /// dari coordinator di tengah evaluasi body, sehingga field dibaca saat
    /// repository masih kosong sekaligus menulis ke `@Published` di tengah
    /// view update — dua sebab terpisah yang sama-sama menghasilkan layar
    /// kosong secara intermiten.
    private func setupView() {
        // Selalu `repository`, tidak pernah `input`. `input` adalah apa yang
        // diminta; `repository` adalah apa yang sudah terselesaikan oleh
        // `loadData()`. Konvensi ini berlaku sama di seluruh UseCase.
        let bankCard = useCase.repository.bankCard

        cardNumberViewModel = createCardNumberViewModel(bankCard)
        cardExpiredViewModel = createCardExpiredViewModel(bankCard)
        cvvViewModel = createCvvViewModel(bankCard)
        phoneNumberViewModel = createPhoneNumberViewModel(bankCard)
    }

    // MARK: - Pembangun sub-ViewModel

    // Semuanya berbentuk fungsi murni yang mengembalikan objek baru, lalu
    // hasilnya di-assign ke property `@Published`. Versi lama mencampur dua
    // gaya: sebagian di-assign ulang, sebagian diubah di tempat. Assign ulang
    // selalu menerbitkan perubahan ke view; mengubah di tempat hanya sampai
    // kalau sub-ViewModel itu sendiri diamati. Satu gaya saja menghilangkan
    // seluruh kelas bug "nilainya berubah tapi layar tidak ikut berubah".

    private func createHeaderBankCardViewModel(
        _ bankCard: BankCard
    ) -> HeaderBankCardViewModel {
        let viewModel = HeaderBankCardViewModel()

        viewModel.colors = bankCard.appearance.hexaColorCodes
        viewModel.cardVendorImage = bankCard.provider.logoImageName
        viewModel.cardImage = ImageViewModel(url: bankCard.appearance.imageUrl)
        viewModel.cardImage.hideFallbackAppearance()
        viewModel.cardName = bankCard.name
        viewModel.cardOwner = bankCard.holder.name

        return viewModel
    }

    private func createCardNumberViewModel(
        _ bankCard: BankCard
    ) -> MenuItemViewModel {
        let cardNumber = bankCard.number
        let viewModel = MenuItemViewModel()

        viewModel.title = R.string.field.cardNumberTitle.text
        viewModel.subtitles = [
            cardNumber.withSeparator(
                separator: Separators.whitespace,
                atEveryIndex: SeparatorIndexes.cardNumber
            )
        ]

        viewModel.rightButtonViewModel.setIcon(
            named: R.image.iconDuplicateBlack.name
        )

        viewModel.isBottomSeparatorVisible = true

        // `cardNumber` ditangkap sebagai nilai, jadi closure ini tidak perlu
        // menyentuh useCase belakangan dan tidak ikut menahan apa pun.
        viewModel.action = { [weak self] in
            guard let self = self else { return }

            cardNumber.copyToClipboard(
                completion: self.copyCardNumberToClipboardCompletion
            )
        }

        return viewModel
    }

    private func createCardExpiredViewModel(
        _ bankCard: BankCard
    ) -> DescriptionVerticalViewModel {
        let expiredDate = bankCard.expiration
            .expireInShortenPeriodFormat
            .convertToDate(format: DateFormats.shortenPeriod)

        return DescriptionVerticalViewModel(
            title: R.string.field.cardExpiredDate.text,
            subtitle: DetailCardInfoScreenViewModel.monthAndYearFormatter.string(
                from: expiredDate ?? DefaultValues.emptyDate
            ),
            isShowSeparator: true
        )
    }

    private func createCvvViewModel(
        _ bankCard: BankCard
    ) -> DescriptionVerticalViewModel {
        let cvv = bankCard.cvv

        return DescriptionVerticalViewModel(
            title: R.string.field.cvvTitle.text,
            subtitle: cvv.isEmpty
                ? DefaultValues.whitespace
                : cvv.suffix(Lengths.cvvNumber).toString,
            isShowSeparator: true
        )
    }

    private func createPhoneNumberViewModel(
        _ bankCard: BankCard
    ) -> DescriptionVerticalViewModel {
        DescriptionVerticalViewModel(
            title: R.string.field.registeredPhoneNumberTitle.text,
            subtitle: bankCard.linkedInfo.phoneNumber,
            isShowSeparator: true
        )
    }

    private func createTipsViewModel() -> TipsViewModel {
        let viewModel = TipsViewModel()

        viewModel.iconImageViewModel.setImage(
            named: R.image.iconExclamation.name
        )

        viewModel.setContent(
            title: DefaultValues.emptyString,
            description: R.string.hint.cardDetailTip.text
        )

        return viewModel
    }

    private func copyCardNumberToClipboardCompletion() {
        messageHandler(
            SuccessCodes.Client.cardNumberCopied.successMessage,
            DefaultValues.emptyAnyDictionary
        )
    }
}
