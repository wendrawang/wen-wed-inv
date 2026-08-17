# Matriks Akses

Aturan lama tim (2022) yang menentukan lapisan mana boleh menyentuh apa.
Dokumen ini adalah sumber kebenaran untuk `callback`, `input`, `output`, dan
`repository` — kalau ada aturan lain di repo ini yang bertentangan dengannya,
yang salah adalah aturan itu.

`V` = boleh, `X` = tidak boleh.

| | Callback&nbsp;Fired | Callback&nbsp;Assignment | Input&nbsp;Read | Input&nbsp;Write | Output&nbsp;Read | Output&nbsp;Write | Repository&nbsp;Read | Repository&nbsp;Write |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Coordinator** | X | V | X | V | V | X | X | X |
| **View Model**  | V | V | X | X | X | X | V | X |
| **Use Case**    | V | X | V | X | V | V | V | V |
| **View**        | X | X | X | X | X | X | X | X |

---

## Yang dikatakan matriks ini

**Arah data punya satu jalur, dan jalurnya searah.** Coordinator menulis
`input`. UseCase membaca `input`, lalu menulis `repository` dan `output`.
ViewModel membaca `repository`. Coordinator membaca `output` untuk diteruskan
ke layar berikutnya. Tidak ada lapisan yang boleh memotong jalur.

**`input` dan `repository` bukan dua nama untuk hal yang sama.** `input` adalah
apa yang diminta; `repository` adalah apa yang sudah terselesaikan. ViewModel
dilarang membaca `input` justru supaya tidak ada yang menampilkan permintaan
seolah-olah itu hasil.

**`output` adalah saluran ke atas, `repository` saluran ke bawah.** `output`
dibaca coordinator untuk mengoper data ke layar berikutnya; `repository` dibaca
ViewModel untuk ditampilkan. Karena itu ViewModel tidak boleh menyentuh
`output`, dan coordinator tidak boleh menyentuh `repository`.

**UseCase tidak boleh memasang callback-nya sendiri.** Callback selalu dipasang
dari luar — oleh coordinator atau ViewModel. UseCase hanya menyalakannya.

**View tidak boleh menyentuh apa pun.** Semua yang dirender datang dari property
ViewModel, tidak pernah langsung dari UseCase.

---

## Kepatuhan kode contoh

`Examples/DetailCardInfo` sudah sesuai:

| Baris | Lapisan | Akses | Status |
|---|---|---|---|
| `useCase.input.bankCard = bankCard` | Coordinator | Input Write | V |
| `useCase.callback.onFetchSucceed = ...` | View Model | Callback Assignment | V |
| `repository.bankCard = input.bankCard` | Use Case | Input Read, Repository Write | V |
| `startFetchSucceed(identifier)` | Use Case | Callback Fired | V |
| `useCase.repository.bankCard` di `setupView()` | View Model | Repository Read | V |
| `DetailCardInfoScreen` | View | — | tidak menyentuh apa pun |

Matriks ini juga membenarkan keputusan menghapus accessor
`var bankCard: BankCard { repository.bankCard }` dari UseCase. ViewModel memang
seharusnya membaca `repository` secara langsung; accessor itu hanya menambah
cara ketiga untuk hal yang sudah punya aturan jelas.

---

## Satu celah yang perlu ditutup

Coordinator boleh **membaca** `output` tetapi tidak boleh **menulisnya**.
Mengoper `output` ke coordinator anak sebagai `Binding` memberikan keduanya:

```swift
// Parent memberi akses tulis yang dilarang matriks
DetailDebitCardInfoCoordinator(
    selectionCoordinatorName: $destinationCoordinatorName,
    sourceCoordinatorName: ...,
    debitCard: $useCase.output.bankCard   // ← Binding = baca DAN tulis
)
```

Selama anaknya tidak pernah menulis, perilakunya tetap benar — tetapi
kepatuhannya bergantung pada disiplin, bukan pada tipe.

Nilai biasa (`let debitCard: BankCard`) bukan penggantinya, karena `output`
tidak `@Published`; nilai yang ditangkap saat body parent berjalan bisa basi
ketika `output` terisi belakangan. Yang dibutuhkan adalah pembacaan hidup tanpa
kemampuan menulis, dan itu cukup sebuah closure:

```swift
struct DetailDebitCardInfoCoordinator: View {
    @Binding var selectionCoordinatorName: String?
    @Binding var sourceCoordinatorName: String?
    let debitCard: () -> BankCard        // baca hidup, tanpa tulis
}

// Di parent
DetailDebitCardInfoCoordinator(
    selectionCoordinatorName: $destinationCoordinatorName,
    sourceCoordinatorName: ...,
    debitCard: { useCase.output.bankCard }
)
```

Nilainya dibaca saat layar di-push, sama segarnya dengan `Binding`, tetapi
kompilator sekarang yang menegakkan aturannya alih-alih review.

---

## Checklist

- [ ] Coordinator tidak membaca `input`, tidak menulis `output`, tidak menyentuh `repository`
- [ ] Coordinator menerima `output` sebagai closure pembaca, bukan `Binding`
- [ ] ViewModel tidak menyentuh `input` maupun `output`
- [ ] ViewModel membaca `repository`, tidak pernah menulisnya
- [ ] UseCase tidak memasang callback-nya sendiri
- [ ] View tidak menyentuh `callback`, `input`, `output`, maupun `repository`
