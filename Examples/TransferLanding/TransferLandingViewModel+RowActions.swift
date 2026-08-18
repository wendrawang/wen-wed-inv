import SwiftUI

/// Dua aksi milik satu baris daftar: menandai favorit, dan memilih penerima.
///
/// Dipisah dari file utamanya semata karena batas 250 baris per file. Isinya
/// dipindah apa adanya.
///
// PERUBAHAN: `private` dilepas dari kedua method di bawah. Keduanya
// dipanggil `createAccountHeadlineViewModel` yang tetap berada di file
// utama, dan `private` di Swift tidak menembus batas file.
extension TransferLandingViewModel {

    func switchFavoriteState(_ bankContact: BankContact) {
        if bankContact.isFavorite {
            var message = DialogCodes.Client.removeRecipientFromFavorite.dialogMessage
            // PERUBAHAN: `[weak self]`.
            message.secondaryButton.customAction = { [weak self] in
                self?.useCase.switchFavoriteState(bankContact: bankContact)
            }
            messageHandler(message, DefaultValues.emptyAnyDictionary)
            return
        }

        useCase.switchFavoriteState(bankContact: bankContact)
    }

    func startSubmission(recipientContact: BankContact) {
        var event = AnalyticManager.instance.analytics.startInquiryTransferSavedRecipient
        event.parameters = [
            .categoryTitle: selectedTransferCategory.title
        ]

        AnalyticManager.instance.track(event)

        useCase.startSubmission(
            data: TransferRecipientUseCase.SubmissionData(
                bank: recipientContact.accountInfo.bank.bankType == .domestic
                    ? recipientContact.accountInfo.bank
                    : Bank(),
                identifier: recipientContact.identifier,
                nickname: recipientContact.nickname,
                accountName: recipientContact.accountInfo.accountName,
                accountFullname: recipientContact.transferInfo.accountFullname,
                accountNumber: recipientContact.accountInfo.accountNumber,
                swiftCode: recipientContact.accountInfo.bank.bankType == .domestic
                    ? DefaultValues.emptyString
                    : recipientContact.accountInfo.bank.code,
                transferCategory: recipientContact.transferInfo.transferCategory,
                nationality: recipientContact.transferInfo.citizenship,
                nccValue: recipientContact.transferInfo.nccValue,
                address: recipientContact.address,
                domicile: recipientContact.domicile,
                accountCategory: recipientContact.accountCategory
            )
        )
    }
}
