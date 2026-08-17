import SwiftUI

struct TransferLandingScreen: ScreenContent {
    @ObservedObject var viewModel: TransferLandingViewModel

    var body: some View {
        ZStack {
            renderNavigationLinks()
            render()
        }
    }

    private func renderCategoryView() -> some View {
        CategoryView(
            viewModel: viewModel.transferCategoryViewModel,
            horizontalPadding: Spaces.medium
        )
        .padding(.top, Spaces.medium)
    }

    private func renderPrivateAccount() -> some View {
        ScrollableView {
            VStack(spacing: DefaultValues.emptyCGFloat) {
                Text(R.string.screen.privateBeneficiariesSelectionSubtitle.text)
                    .foregroundColor(Colors.Black.primary)
                    .font(Fonts.openSansBold(ofSize: FontSizes.heading3))
                    .textAlignment(.leading)
                    .padding(.top, Spaces.medium)
                    .padding(.horizontal, Spaces.medium)

                BankAccountSelectionWidget(
                    viewModel: viewModel.privateAccountSelectionWidgetViewModel
                )
            }
        }
        .setHidden(viewModel.selectedTransferCategory != .privateAccount)
    }

    private func renderSavedRecipientList() -> some View {
        InfiniteScrollListView(
            viewModel: viewModel.infiniteScrollViewModel,
            items: $viewModel.accountHeadlineViewModels,
            headerView: { DefaultValues.emptyAnyView },
            footerView: { Color.clear.frame(height: Spaces.medium) },
            emptyView: renderEmptyState,
            rowView: { item in
                renderRecipientItem(item)
            }
        )
    }

    private func renderRecipientItem(
        _ accountHeadlineViewModel: AccountHeadlineViewModel
    ) -> some View {
        VStack(spacing: DefaultValues.emptyCGFloat) {
            Text(accountHeadlineViewModel.sectionTitle)
                .font(Fonts.openSansBold(ofSize: FontSizes.small))
                .foregroundColor(Colors.Black.primary)
                .textAlignment(.leading)
                .padding(.horizontal, Spaces.medium)
                .padding(.bottom, Spaces.halfSmall)
                .setHidden(accountHeadlineViewModel.sectionTitle.isEmpty)

            AccountHeadlineView(
                viewModel: accountHeadlineViewModel,
                style: BankAccountHeadlineViewStyle()
            )
            .padding(.horizontal, Spaces.medium)
            .padding(.vertical, Spaces.halfSmall)
        }
    }

    private func renderSearchView() -> some View {
        VStack(spacing: DefaultValues.emptyCGFloat) {
            Text(R.string.sectionTitle.recipientInfo.text)
                .font(Fonts.openSansBold(ofSize: FontSizes.micro))
                .foregroundColor(Colors.Gray.primary)
                .textAlignment(.leading)
                .padding(.bottom, Spaces.halfSmall)

            VStack(spacing: DefaultValues.emptyCGFloat) {
                SearchBarView(
                    viewModel: viewModel.searchBarViewModel,
                    horizontalPadding: Spaces.small
                )
                .padding(.vertical, Spaces.halfSmall)
                .applyRoundedRectangleBorder()
            }
            .padding(.top, Spaces.small)
            .padding(.horizontal, Spaces.medium)
        }
    }

    private func renderNewRecipientButton() -> some View {
        MenuItemView(
            viewModel: viewModel.newRecipientMenuItemViewModel,
            style: PlainMenuItemViewStyle(),
            iconStyle: MediumLargeIconImageViewStyle()
        )
        .padding(.horizontal, Spaces.smallest)
    }

    private func renderSearchSectionTitle() -> some View {
        Text(R.string.sectionTitle.searchResults.text)
            .font(Fonts.openSansBold(ofSize: FontSizes.small))
            .foregroundColor(Colors.Black.primary)
            .textAlignment(.leading)
            .padding(.horizontal, Spaces.medium)
            .padding(.bottom, Spaces.halfSmall)
            .setHidden(viewModel.searchBarViewModel.searchKeyword.isEmpty)
    }

    private func renderContentWithRecipientList() -> some View {
        VStack(spacing: DefaultValues.emptyCGFloat) {
            renderSearchView()
            renderNewRecipientButton()
            renderSearchSectionTitle()
            renderSavedRecipientList()
        }
        .setHidden(viewModel.selectedTransferCategory == .privateAccount)
    }

    private func renderScreen() -> some View {
        VStack(spacing: DefaultValues.emptyCGFloat) {
            renderCategoryView()

            ZStack {
                renderContentWithRecipientList()
                renderPrivateAccount()
            }
        }
        .disabled(!viewModel.isUserInteractionEnabled)
    }

    private func render() -> some View {
        ZStack {
            if #available(iOS 14.0, *) {
                AnyView(
                    renderScreen().ignoresSafeArea(.keyboard)
                )
            } else {
                renderScreen()
            }
        }
    }
}
