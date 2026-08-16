import SwiftUI

struct DetailCardInfoScreen: ScreenContent {

    /// Tanpa nilai default.
    ///
    /// `@ObservedObject var viewModel = DetailCardInfoScreenViewModel()` membuat
    /// layar ini bisa dibangun tanpa ViewModel dan tetap kompilasi — hasilnya
    /// layar kosong tanpa pesan error. Menjadikannya wajib memindahkan
    /// kesalahan itu ke waktu kompilasi.
    @ObservedObject var viewModel: DetailCardInfoScreenViewModel

    var body: some View {
        ZStack {
            renderNavigationLinks()
            render()
        }
    }

    private func renderHeaderBankCardView() -> some View {
        HeaderBankCardView(
            viewModel: viewModel.headerBankCardViewModel
        )
    }

    private func renderCardNumberView() -> some View {
        MenuItemView(
            viewModel: viewModel.cardNumberViewModel,
            style: ReversedPlainMenuItemViewStyle(),
            iconStyle: MediumIconImageViewStyle()
        )
        .padding(.horizontal, Spaces.smallest.negativeValue)
    }

    private func renderCardExpiredView() -> some View {
        DescriptionVerticalView(
            viewModel: viewModel.cardExpiredViewModel,
            style: MicroGrayDescriptionVerticalViewStyle()
        )
    }

    private func renderCvvView() -> some View {
        DescriptionVerticalView(
            viewModel: viewModel.cvvViewModel,
            style: MicroGrayDescriptionVerticalViewStyle()
        )
    }

    private func renderPhoneNumber() -> some View {
        DescriptionVerticalView(
            viewModel: viewModel.phoneNumberViewModel,
            style: MicroGrayDescriptionVerticalViewStyle()
        )
        .setHidden(
            viewModel.bankCardType == .creditCard
                || viewModel.phoneNumberViewModel.isEmpty
        )
    }

    private func renderCardDetailView() -> some View {
        CardView(
            horizontalPadding: DefaultValues.emptyCGFloat,
            paddingTop: Spaces.halfSmall,
            paddingBottom: Spaces.small
        ) {
            VStack(spacing: DefaultValues.emptyCGFloat) {
                renderCardNumberView()

                HStack(spacing: Spaces.halfSmall) {
                    renderCardExpiredView()
                    renderCvvView()
                }
                .padding(.horizontal, Spaces.small)

                renderPhoneNumber()
                    .padding(.horizontal, Spaces.small)
            }
        }
    }

    private func renderTipsView() -> some View {
        TipsView(
            viewModel: viewModel.tipsViewModel,
            style: PrimaryTipsViewStyle()
        )
        .padding(.horizontal, Spaces.medium)
        .padding(.vertical, Spaces.large)
    }

    private func render() -> some View {
        VStack(spacing: Spaces.small.negativeValue) {
            renderHeaderBankCardView()
            renderCardDetailView()
            renderTipsView()
            Spacer()
        }
        .edgesIgnoringSafeArea(.all)
    }
}
