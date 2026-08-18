import SwiftUI

/// Penyiapan sub-ViewModel milik Transfer Landing.
///
/// Dipisah dari file utamanya semata karena batas 250 baris per file.
/// Isinya dipindah apa adanya — tidak ada satu baris pun yang berubah.

extension TransferLandingViewModel {
    func setupPrivateBankAccountSelectionWidgetViewModel() {
        privateAccountSelectionWidgetViewModel.adapter = BeneficiaryAccountSelectionAdapter(
            analytic: AnalyticManager.instance.analytics.hitTransferAccountSelect
        )

        // PERUBAHAN: `[weak self]`.
        privateAccountSelectionWidgetViewModel.onReceiveError = { [weak self] error in
            self?.messageHandler(error.message, DefaultValues.emptyAnyDictionary)
        }

        privateAccountSelectionWidgetViewModel.setHeight(.infinity)
        // PERUBAHAN: `[weak self]`.
        privateAccountSelectionWidgetViewModel.onChangeValue = { [weak self] bankAccount in
            self?.didSelectedPrivateBankAccount(bankAccount)
        }
    }

    private func didSelectedPrivateBankAccount(_ bankAccount: BankAccount) {
        useCase.startTransferToOwnAccount(
            bankAccount: bankAccount,
            transferCategory: selectedTransferCategory
        )
    }
}

extension TransferLandingViewModel {
    func setupTransferCategoryViewModel() {
        if !transferCategoryViewModel.categoryItemViewModels.isEmpty {
            return
        }

        selectedTransferCategory = useCase.repository.transferCategory
        transferCategoryViewModel.categoryItemViewModels = useCase
            .repository
            .transferCart
            .availableNewTransferCategories
            .convertToCategoryItemViewModels()

        // PERUBAHAN: `[weak self]`.
        transferCategoryViewModel.onSelectedItem = { [weak self] item in
            self?.onSelectedCategoryItem(item)
        }

        transferCategoryViewModel.selectByValue(selectedTransferCategory.rawValue)
    }

    private func onSelectedCategoryItem(_ item: CategoryItemViewModel) {
        let newSelectedTransferCategory = TransferCategory(
            rawValue: item.value
        ) ?? .unspecified

        if selectedTransferCategory == newSelectedTransferCategory {
            return
        }

        UIApplication.shared.endEditing()
        selectedTransferCategory = newSelectedTransferCategory
        searchBarViewModel.flushData()
        bankSelectionAdapter.removeAllData()
        bankSelectionAdapter.isValas = selectedTransferCategory == .valas
        privateAccountSelectionWidgetViewModel.clearSelection()
        useCase.setSelectedTransferCategory(selectedTransferCategory)
        reloadData()
    }
}

// PERUBAHAN: konformansi baru, supaya coordinator bisa menulis
// `viewModel.binding(\.activeDestinationCoordinatorName)`.
//
// Kalau nanti dibutuhkan di banyak layar, pindahkan ke
// `ScreenContentViewModel` supaya seluruh ViewModel ikut.
extension TransferLandingViewModel: PropertyBindable {}
