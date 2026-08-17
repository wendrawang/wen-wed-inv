# Temuan di Transfer Landing

Layar panjang dengan list, pencarian, pagination, dan sembilan tujuan navigasi.
Jauh lebih kaya daripada Detail Card Info, dan karena itu memperlihatkan
persoalan yang tidak muncul di layar pendek.

Diurutkan berdasarkan dampak, bukan urutan ditemukan.

---

## Yang sudah benar duluan

Sebelum daftar masalah, satu hal yang layak dicatat: **`navigationLinks` yang
berbentuk kamus closure itu memang bekerja sebagai lazy.**

```swift
private func createNavigationLinks() -> AnyView {
    if let destination = destinationCoordinatorName,
       let navigationLink = navigationLinks[destination] {
        return navigationLink()
    }
    return DefaultValues.emptyAnyView
}
```

Hanya satu tujuan yang benar-benar dibangun — yang cocok dengan
`destinationCoordinatorName`. Bandingkan dengan `DetailDebitCardPinCoordinator`
yang membangun **semua** tujuannya sekaligus di dalam `Group`. Di layar dengan
sembilan tujuan, perbedaannya besar, dan naluri yang melahirkannya benar.

Yang perlu diperbaiki adalah biaya pencariannya, bukan idenya.

---

## 1. Satu penerbitan per baris list

Ini kandidat terkuat untuk fps di layar ini, dan perbaikannya paling kecil.

```swift
@Published var accountHeadlineViewModels = [AccountHeadlineViewModel]()

private func setupRecipientList() {
    accountHeadlineViewModels.removeAll()          // penerbitan #1

    for data in selectedResponseRecipientTransfers {
        for bankContact in data.bankContacts {
            ...
            accountHeadlineViewModels.append(...)  // penerbitan #2, #3, #4, …
        }
    }

    if searchBarViewModel.searchKeyword.isEmpty {
        accountHeadlineViewModels = accountHeadlineViewModels
            .transformToSectionedItems()           // penerbitan terakhir
    }
}
```

Setiap `append` ke property `@Published` menerbitkan `objectWillChange`. Satu
halaman berisi 20 kontak berarti **22 invalidasi berturut-turut** — dan karena
invalidasi `ObservableObject` bersifat object-level, tiap satunya
meng-invalidasi seluruh `TransferLandingScreen` **dan** `Screen` di atasnya.

SwiftUI menggabungkan penerbitan dalam satu putaran runloop, jadi sebagian
tertelan. Tapi tidak ada yang menjamin semuanya jatuh di putaran yang sama,
apalagi saat respons jaringan datang di tengah scroll.

Ada beban kedua yang lebih halus: `setupRecipientList` membangun ulang
**seluruh** daftar dari semua halaman setiap kali satu halaman baru datang.
Memuat halaman ke-5 berarti membangun ulang lima halaman view model. Dan karena
`AccountHeadlineViewModel` adalah class, semua barisnya mendapat identitas baru
— seluruh list dirender ulang dari nol, bukan hanya baris yang bertambah.

### Perbaikan

```swift
private func setupRecipientList() {
    var models = [AccountHeadlineViewModel]()

    for data in selectedResponseRecipientTransfers {
        for bankContact in data.bankContacts {
            models.append(accountHeadlineViewModel(for: bankContact))
        }

        infiniteScrollViewModel.updatePagination(data.pagination)
    }

    if searchBarViewModel.searchKeyword.isEmpty {
        models = models.transformToSectionedItems()
    }

    accountHeadlineViewModels = models   // tepat satu penerbitan

    if models.isEmpty {
        setupEmptyState()
    }
}
```

Bangun ke array lokal, terbitkan sekali di akhir. Dari 22 penerbitan jadi satu.

### Beban kedua: identitas baris, dan posisi scroll

Menerbitkan sekali tidak cukup. Beban kedua di atas — daftar dibangun ulang
dari **semua** halaman setiap kali satu halaman baru datang — punya akibat yang
langsung terasa penggunanya: pengguna scroll ke bawah, halaman 2 masuk, list
melompat kembali ke atas.

Sebabnya identitas. `AccountHeadlineViewModel` adalah class, jadi baris halaman
1 yang dibangun ulang menjadi objek berbeda meski isinya sama persis. Bagi
SwiftUI itu list yang sepenuhnya baru, bukan list lama yang bertambah panjang,
dan posisi scroll tidak punya tempat untuk bertahan.

Perbaikannya cache per kontak — bangun sekali, pakai lagi:

```swift
private var accountHeadlineViewModelCache = [String: AccountHeadlineViewModel]()

private func accountHeadlineViewModel(
    for bankContact: BankContact
) -> AccountHeadlineViewModel {
    let key = String(describing: bankContact.identifier)

    if let cached = accountHeadlineViewModelCache[key] {
        return cached
    }

    let model = makeAccountHeadlineViewModel(bankContact)
    accountHeadlineViewModelCache[key] = model
    return model
}
```

Cache dikosongkan **bersamaan** dengan `accountHeadlineViewModels.removeAll()`
di `reloadData()` dan `flushData()` — jangan di salah satunya saja. `bankContact`
ikut tertangkap di dalam closure baris, jadi setelah favorit di-toggle atau kata
kunci berubah, barisnya memang harus dibangun ulang; dan kedua jalur itu
sama-sama melewati `reloadData()`.

Satu catatan kejujuran: versi lama pun membangun ulang seluruh baris, jadi
lompatan scroll ini bukan sesuatu yang lahir dari perbaikan §1 — ia sudah ada
sebelumnya dan baru terlihat setelah `.id()` dilepas, karena sebelum itu seluruh
layar memang dirobohkan setiap kali. Kalau setelah cache ini posisinya masih
melompat, tersangka berikutnya `transformToSectionedItems()`: kalau ia
menciptakan objek header baru setiap kali dipanggil, identitas di sekitar
barisnya tetap berganti. Itu perlu dibaca langsung, bukan ditebak.

---

## 2. `.id(destinationCoordinatorName)` merobohkan seluruh layar

```swift
Screen {
    TransferLandingScreen(viewModel: createViewModel())
}
.id(destinationCoordinatorName)
```

`.id()` menentukan identitas view. Setiap kali `destinationCoordinatorName`
berubah — yaitu **setiap kali pengguna menuju tujuan mana pun, dan setiap kali
kembali** — SwiftUI menganggapnya view yang sepenuhnya berbeda: seluruh
`Screen` dirobohkan dan dibangun ulang dari nol.

Yang ikut hilang: posisi scroll, isi list, kata kunci pencarian, state pagination,
dan seluruh `ScreenContentViewModel`. Lalu semuanya dimuat ulang.

### Koreksi: `.id()` bukan tambalan

Saya sempat menulis di sini bahwa `.id()` adalah tambalan untuk `AnyView` yang
menghapus structural identity. **Itu keliru.** Menghapusnya membuat navigasi ke
layar berikutnya berhenti bekerja sama sekali.

Mekanismenya: `createNavigationLinks()` hanya membangun tautan untuk tujuan
yang cocok dengan `destinationCoordinatorName`, jadi saat nilainya masih nil
tidak ada satu pun tautan anak di dalam pohon view. Ketika pengguna menekan
sesuatu dan nilainya berubah, tautan anak baru **muncul dengan selection-nya
sudah sama dengan tag-nya**. `NavigationView` di iOS 13–14 tidak melakukan push
untuk tautan yang disisipkan dalam keadaan sudah terpilih — ia perlu melihat
perpindahan dari tidak-terpilih ke terpilih. `.id()` membuat subtree-nya
dibangun ulang sebagai identitas baru, sehingga tautannya terpasang di pohon
yang benar-benar baru dan push-nya terjadi.

Konsekuensi keduanya: **`.id()` tidak bisa dipakai bersama
`LazyNavigationLink`.** Builder-nya hanya berjalan sekali lalu hasilnya
disimpan, jadi nilai `.id()` beku pada pembacaan pertama — nil — dan tidak
pernah berubah lagi.

Biayanya tetap nyata: seluruh `Screen` dirobohkan dan dibangun ulang setiap kali
tujuan berubah dan setiap kali kembali, membawa serta posisi scroll, isi list,
dan kata kunci pencarian. Tetapi menghilangkannya berarti mengganti cara tautan
anak disisipkan — misalnya menyisipkan tautannya lebih dulu lalu menyalakan
selection-nya pada putaran runloop berikutnya. Itu perubahan yang harus
dikerjakan sambil menjalankan aplikasinya, bukan ditebak dari kode.

---

## 3. Sepuluh retain cycle, dan dua di antaranya berkalikan dengan panjang list

`setUseCase` memasang delapan closure lewat referensi method:

```swift
useCase.callback.onStartSubmissionLoading = startScreenLoading
useCase.callback.onStopSubmissionLoading = stopScreenLoading
useCase.callback.onStartSwitchFavoriteLoading = startScreenLoading
useCase.callback.onStopSwitchFavoriteLoading = stopScreenLoading
useCase.callback.onSwitchFavoriteSucceed = reloadData
useCase.callback.onSubmissionFailed = didReceiveError
useCase.callback.onFetchSucceed = setupRecipientList
useCase.callback.onFetchFailed = didReceiveError
self.useCase = useCase
```

Semuanya menangkap `self` kuat, dan `self` menyimpan `useCase`. Lingkaran
tertutup delapan kali.

Yang lebih berat ada di list, karena jumlahnya mengikuti jumlah baris:

```swift
accountHeadlineViewModel.showFavoriteButton(action: {
    self.switchFavoriteState(bankContact)
})

accountHeadlineViewModel.action = {
    self.startSubmission(recipientContact: bankContact)
}
```

Setiap baris menyimpan dua closure yang menahan ViewModel, dan barisnya
disimpan di `accountHeadlineViewModels` milik ViewModel itu sendiri. Daftar 100
kontak berarti 200 lingkaran.

Dua lagi di tempat lain:

```swift
searchBarViewModel.onStartSearch = { _ in self.reloadData() }

privateAccountSelectionWidgetViewModel.onReceiveError = { error in
    self.messageHandler(error.message, DefaultValues.emptyAnyDictionary)
}
```

### Perbaikan

Semuanya bentuknya sama:

```swift
useCase.callback.onFetchSucceed = { [weak self] in self?.setupRecipientList() }

accountHeadlineViewModel.action = { [weak self] in
    self?.startSubmission(recipientContact: bankContact)
}

searchBarViewModel.onStartSearch = { [weak self] _ in self?.reloadData() }
```

Ini yang harus diuji lebih dulu, dan ujiannya murah:

```swift
func testTransferLandingViewModelIsReleased() {
    let useCase = TransferLandingUseCase()
    useCase.renewIdentifier()

    let sut = TransferLandingViewModel()
    sut.setUseCase(useCase)

    trackForMemoryLeaks([sut, useCase])
}
```

### Koreksi: `onStartFetchLoading` juga harus diputus

Saya sempat menulis di sini bahwa `onStartFetchLoading =
infiniteScrollViewModel.startLoading` **bukan** lingkaran, karena ia menangkap
`infiniteScrollViewModel` dan bukan `self`. Bagian pertamanya benar; kesimpulannya
tidak. Alasan yang saya pakai — "`infiniteScrollViewModel` tidak memegang
ViewModel" — tidak pernah saya buktikan, dan saya belum pernah membaca
`PaginationScreenContentViewModel`.

Yang bisa dipastikan dari kode yang ada: kedua baris itu menahan
`infiniteScrollViewModel` secara kuat **dari dalam `useCase`**, dan
`infiniteScrollViewModel` adalah milik ViewModel. Kalau base pagination memasang
handler "muat halaman berikutnya" ke `infiniteScrollViewModel` lewat referensi
method, rantainya tertutup:

```
viewModel → useCase → callback → infiniteScrollViewModel → viewModel
```

`[weak self]` memutusnya di mata rantai pertama tanpa perlu tahu isi base-nya,
dan perilakunya tidak berubah — `infiniteScrollViewModel` dijamin ada selama
ViewModel-nya ada:

```swift
useCase.callback.onStartFetchLoading = { [weak self] in
    self?.infiniteScrollViewModel.startLoading()
}
```

Kalau setelah ini `testLoadDataDoesNotRetainViewModel` masih merah, mata rantai
terakhirnya ada di dalam base pagination dan harus diperbaiki di sana.

---

## 4. Kamus sembilan closure dibangun ulang setiap render

```swift
private var navigationLinks: [String: TypeAliases.NavigationHandler] {[
    TransferTransactionAmountCoordinator.named: { AnyView(...) },
    ...
]}
```

Ini **computed property**, jadi setiap akses membangun kamus baru berisi
sembilan closure. Dan `createNavigationLinks()` mengaksesnya — lalu
`createNavigationLinks` dipanggil dari `renderNavigationLinks()` di dalam `body`
layar.

Jadi setiap evaluasi body: satu Dictionary plus sembilan konteks closure
dialokasikan, hanya untuk mengambil satu entri lalu dibuang.

### Perbaikan

`switch` tidak mengalokasikan apa pun dan hanya membangun cabang yang cocok:

```swift
private func createNavigationLinks() -> AnyView {
    guard let destination = destinationCoordinatorName else {
        return DefaultValues.emptyAnyView
    }

    switch destination {
    case TransferTransactionAmountCoordinator.named:
        return AnyView(TransferTransactionAmountCoordinator(...))

    case TransferDebitAccountSelectionCoordinator.named:
        return AnyView(TransferDebitAccountSelectionCoordinator(...))

    default:
        return DefaultValues.emptyAnyView
    }
}
```

Lebih panjang dibaca, tetapi nol alokasi dan tetap lazy — sifat yang membuat
versi kamusnya bagus tidak hilang.

---

## 5. Yang sudah kita kenal, muncul lagi di sini

Ketiganya sudah dibahas di [SCREEN_PATTERN.md](SCREEN_PATTERN.md) dan
perbaikannya persis sama:

- `private let viewModel = TransferLandingViewModel()` — dialokasikan ulang
  setiap struct di-init.
- `@State private var useCase = TransferLandingUseCase()` — dialokasikan lalu
  dibuang setiap struct di-init.
- Cabang `if selectionCoordinatorName != named { … return TransferLandingViewModel() }`
  — mengirim ViewModel kosong ke layar. Di sini ia juga memanggil
  `useCase.flushData()`, yang menjalankan `repository = Repository()` **dan**
  `output = Output()` — mengosongkan seluruh hasil transfer yang sedang
  disusun.

---

## 6. Yang menjadi nyata di sini, dan tidak di layar sebelumnya

**`renewIdentifier()` yang membuang fetch berjalan.** Di Detail Card Info
dugaan ini saya coret karena `loadData()`-nya sinkron. Di sini `loadData(pageNumber:searchKeyword:)`
memanggil network sungguhan, dan `renewIdentifier()` di awalnya memang
disengaja — supaya hasil pencarian lama dibuang saat kata kunci berubah. Tetapi
`createUseCase()` di coordinator **juga** memanggilnya pada setiap evaluasi
body, dan itu bisa membuang halaman yang sedang dimuat tanpa jejak.

**`callback.onStartFetchLoading()` dipanggil langsung.** Di sini jalurnya
melewati jaringan, jadi risiko penulisan `@Published` dari thread selain main
bukan lagi teoretis. Pakai `startFetchLoading()`.

**Penerbitan tanpa pembanding nilai.**

```swift
var selectedTransferCategory: TransferCategory = .unspecified {
    willSet { self.objectWillChange.send() }
}
```

Menerbitkan pada setiap penulisan, termasuk saat nilainya sama. Di `willSet`
nilai lama masih tersedia, jadi penjagaannya satu baris:

```swift
willSet {
    guard newValue != selectedTransferCategory else { return }
    objectWillChange.send()
}
```

---

## Urutan yang disarankan

1. **Test retain cycle** (§3). Paling murah, dan jumlahnya berkalikan dengan
   panjang list — kalau terkonfirmasi, ini juga persoalan memori, bukan cuma
   kerapian.
2. **Satu penerbitan untuk list** (§1). Perubahan kecil, kandidat terkuat untuk
   fps di layar ini. Ukur dengan `RenderCounter` sebelum dan sesudah.
3. **`switch` menggantikan kamus** (§4). Mekanis, tanpa perubahan perilaku.
4. **Sisanya** (§5, §6) mengikuti pola yang sudah ada.
5. **`.id()`** (§2) paling akhir, karena terikat pada keputusan navigasi yang
   masih menggantung.
