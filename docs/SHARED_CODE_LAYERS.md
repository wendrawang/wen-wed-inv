# Merapikan yang dipakai bersama

Daftar apa saja yang layak naik ke lapis bersama, urutan mengerjakannya, dan
satu jebakan penamaan yang menentukan apakah hasilnya rapi atau jadi tempat
buangan baru.

Yang **sudah terlihat** di kode transfer ditandai jumlah pemakaiannya. Sisanya
kandidat yang biasanya ada di aplikasi sebesar ini — periksa dulu, jangan
dianggap ada.

---

## Aturan memutuskan, satu kalimat

**Kalau sebuah file tidak menyebut satu pun tipe di luar dirinya, ia daun dan
bisa dipindah sekarang.**

Itu saja. Bukan ukurannya, bukan seberapa sering dipakai. `Spaces` dipakai 18
kali dan tetap nol risiko; satu file 30 baris yang menyebut `R.string` menyeret
seluruh persoalan resource.

---

## Lapis 1 — Design tokens

Nilai visual murni. Tidak menyebut apa pun, jadi tidak ada yang bisa salah.

| | Status |
|---|---|
| `Spaces` | terlihat, 18× |
| `IconSizes` | terlihat, 1× |
| Colors / warna semantik | periksa |
| Fonts / typography | periksa |
| `CornerRadius`, `BorderWidths`, `Opacity` | periksa |
| Durasi animasi | periksa |
| Shadow / elevation | periksa |

**Kerjakan ini pertama.** Selain nol risiko, ia jadi fondasi lapis 4 dan 5 —
komponen menyebut token, tidak sebaliknya.

Satu hal yang membedakan token bagus dari konstanta biasa: namanya menyebut
**peran**, bukan nilai. `Spaces.small` bertahan saat desainnya berubah;
`Spaces.eight` tidak.

## Lapis 2 — Tipe dan extension murni

| | Status |
|---|---|
| `TypeAliases` | terlihat, 1× |
| `UIApplication.endEditing()` | terlihat, 1× |
| Extension `String`, `Date`, `Int`, `Array` | periksa — `nextNumber`, `ordinalText` sudah terlihat |
| `.invisible()`, `.setHidden()` | terlihat — modifier, ikut ke lapis UI |
| Property wrapper sendiri | periksa |

Sama murninya dengan lapis 1. Bedanya hanya sebagian butuh `SwiftUI` atau
`UIKit`, jadi pisahkan target yang butuh UI dari yang tidak — supaya lapis
non-UI bisa dipakai test dan lapisan domain tanpa menyeret SwiftUI.

## Soal `TypeAliases` — jangan dipindah sebagai satu blok

Naluri Anda benar, tapi kriterianya bukan "primitif atau bukan". Yang benar:

> **Sebuah alias tinggal di target yang sama dengan tipe yang disebutnya.**

```swift
typealias VoidHandler = () -> Void                    // Core
typealias StringHandler = (String) -> Void            // Core
typealias ResponseErrorHandler = (ResponseError) -> Void   // Domain — menyebut model
typealias NavigationHandler = () -> AnyView           // Navigation — menyebut SwiftUI
```

Kalau `ResponseErrorHandler` dipaksa masuk Core, Core harus melihat
`ResponseError`, dan lapis paling bawah jadi tahu model — arah yang salah, dan
sekali itu terjadi semua model ikut tertarik ke bawah.

### Ada persoalan yang lebih mendasar di sini

Satu `enum TypeAliases` yang menampung semuanya **memaksa satu file tahu setiap
lapis.** Bentuk itu sendiri yang menghalangi, bukan isinya.

Jadi jangan pindahkan `TypeAliases` sebagai satu blok. Bubarkan: taruh tiap
alias di dekat yang dilayaninya — `ResponseErrorHandler` di sebelah
`ResponseError`, `NavigationHandler` di `Navigation`. Yang tersisa di Core hanya
segelintir alias yang benar-benar tidak menyebut apa pun.

Sekalian pertimbangkan: sebagian alias itu tidak memberi apa-apa.
`(String) -> Void` lebih jelas dibaca langsung daripada `TypeAliases.StringHandler`,
dan tidak menuntut siapa pun mengingat isinya. Yang layak dipertahankan adalah
alias yang menyembunyikan bentuk **rumit**, bukan yang menamai bentuk sederhana.

---

## Lapis 3 — Konstanta domain

| | Status |
|---|---|
| `Currencies` | terlihat, 2× |
| Kode error / `DialogCodes` | terlihat — tapi menyebut `R.string`, lihat lapis 6 |
| Regex validasi, panjang minimum/maksimum | periksa |
| Kunci `UserDefaults`, nama notifikasi | periksa |

**Ini bukan design system.** `Currencies` sering ikut terbawa ke folder token
karena sama-sama "konstanta", padahal ia aturan bisnis. Kalau tercampur, lapis
UI jadi bergantung pada domain tanpa ada yang menyadarinya.

## Lapis 4 — Formatter dan converter

| | Status |
|---|---|
| `DateFormatter` bersama | terlihat di Detail Card Info — `monthAndYearFormatter` |
| Formatter mata uang / nominal | periksa |
| `transformToSectionedItems()` | terlihat |
| `convertToCategoryItemViewModels()`, `convertToAccountHeadlineViewModel()` | terlihat |

Dua catatan.

`DateFormatter` **mahal dibuat** — jadikan `static let`, dan pin `locale`-nya ke
`en_US_POSIX` kalau formatnya format tetap, bukan format tampilan. Ini sudah
dibahas di `SCREEN_PATTERN.md`.

Converter `convertToXxxViewModel()` **bukan** kandidat lapis bersama kalau ia
menyebut tipe fitur. `convertToAccountHeadlineViewModel()` menyebut `BankContact`
— itu milik fitur transfer, biarkan di sana. Yang naik hanya yang benar-benar
umum seperti `transformToSectionedItems()`.

## Lapis 5 — Style dan komponen

| | Status |
|---|---|
| `SearchTextFieldViewStyle` dan style lain | terlihat |
| `TextFieldViewModel`, `SearchBarViewModel` | terlihat |
| `MenuItemViewModel`, `CategoryViewModel` | terlihat |
| `EmptyStateViewModel`, `InfiniteScrollViewModel` | terlihat |
| `ImageViewModel`, `NavigationBarViewModel` | terlihat |

Menyebut lapis 1 dan 2, jadi kerjakan setelahnya. Ini juga tempat pertama yang
bukan sekadar pemindahan — komponen punya perilaku, jadi bacalah dulu apakah ada
yang diam-diam menyebut fitur tertentu.

`AccountHeadlineViewModel` **bukan** komponen bersama — ia baris daftar penerima,
milik transfer.

## Lapis 6 — Resource

`R.string`, `R.image`, dan semua yang menyebutnya (`DialogCodes`).

Ditunda karena `R` menjadi per-module begitu masuk package — lihat
[MODULARIZATION.md](MODULARIZATION.md). Selama masih satu target, memindahkan
file-nya tidak menyelesaikan apa pun.

## Lapis 7 — Base UI

`Screen`, `ScreenContentViewModel`, `PaginationScreenContentViewModel`, dan
`AppState`.

Terakhir, karena menyebut **semua** yang di atas. Kalau lapis 1–6 sudah beres,
ini pekerjaan mekanis. Kalau belum, ini proyek tersendiri.

---

## Jebakan penamaan

Godaan terbesar saat merapikan adalah membuat satu folder `Common/`, `Utils/`,
`Helpers/`, atau `Shared/`. Semuanya berakhir sama: apa pun yang tidak jelas
tempatnya masuk ke sana, dan dalam setahun folder itu jadi bagian yang paling
tidak bisa dipahami di seluruh repo — karena namanya tidak pernah menolak apa
pun.

Nama folder harus bisa **menolak** sesuatu. `DesignTokens` menolak
`Currencies`. `Formatters` menolak `SearchBarViewModel`. `Common` tidak menolak
apa pun.

Kalau ada file yang tidak jelas masuk mana, itu biasanya tanda file-nya
mengerjakan dua hal — pecah dulu, jangan cari folder yang lebih longgar.

`DefaultValues` contohnya: `emptyString` konstanta murni, `emptyAnyView` urusan
UI, `emptyAnyDictionary` bentuk parameter analytic. Tiga lapis berbeda dalam
satu tipe. Tidak harus dipecah sekarang, tapi jangan tambah isinya.

---

## Urutan yang disarankan

1. **Lapis 1**, seluruhnya. Nol risiko, dan fondasi bagi sisanya.
2. **Lapis 2**, pisahkan yang butuh UI dari yang tidak.
3. **Lapis 3**, sekalian memisahkan konstanta domain dari token — ini biasanya
   yang paling banyak salah tempat hari ini.
4. **Berhenti dan nilai ulang.** Tiga lapis pertama sudah membuat lapis
   berikutnya jauh lebih mudah, dan ketiganya bisa dikerjakan tanpa menyentuh
   satu pun layar.
5. Lapis 4–5 saat menyentuh fiturnya, bukan sebagai proyek terpisah.
6. Lapis 6–7 saat memecah ke package benar-benar dimulai.

Selama masih satu target, ini semua **pemindahan folder** — belum ada `public`,
belum ada `Package.swift`, belum ada resource yang pindah bundle. Justru itu
yang membuatnya murah, dan itu alasan mengerjakannya lebih dulu.
