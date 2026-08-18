# `NavigationStack` atau `UINavigationController`

Kalau minimum iOS bisa dinaikkan ke 16, jawabannya **`NavigationStack`** —
dan infrastruktur yang kita bangun justru menyusut, bukan bertambah.

---

## Perbandingannya langsung

| | `NavigationStack` | `UINavigationController` + `UIHostingController` |
|---|---|---|
| Tumpukan sebagai data | **bawaan** (`path`) | dibangun sendiri (array view controller) |
| Push / pop / pop ke langkah tertentu | operasi array | API UIKit, sudah matang |
| Tujuan dibangun saat di-push | **bawaan** | bawaan |
| Umur objek | terikat `path`; SwiftUI yang melepas | deterministik, `pop` melepas controller |
| Transisi kustom antar layar | terbatas | **penuh** |
| Gestur pop interaktif | otomatis, tidak bisa diatur halus | bisa diatur, tapi harus diurus manual saat bar disembunyikan |
| Bar navigasi sendiri | `.toolbar(.hidden)` | sembunyikan bar UIKit |
| Layar UIKit lama ikut masuk | perlu `UIViewControllerRepresentable` | **native** |
| Layar `NavigationView` lama ikut masuk | perlu "pulau" | perlu "pulau" |
| Kematangan | 16.0–16.3 berisik, tenang di 16.4+ | matang belasan tahun |
| Arah Apple | **yang dikembangkan** | dirawat, tidak dikembangkan |
| Biaya jangka panjang | tidak ada jembatan | **jembatan permanen** |

Dua baris terakhir yang menentukan, dan keduanya menjawab pertanyaan Anda soal
bridging.

### Soal "Apple pasti mendorong SwiftUI"

Betul arahnya, tapi hati-hati dengan kesimpulannya. UIKit **tidak akan hilang** —
ia alas tempat SwiftUI berjalan, dan Apple akan terus merawatnya. Jadi argumen
"UIKit akan mati" tidak jujur, dan bukan itu alasannya.

Alasannya **di mana friksinya menumpuk.**

Dengan navigasi UIKit + layar SwiftUI, Anda memiliki sebuah jembatan: kejanggalan
`UIHostingController`, safe area, keyboard, delegate gestur, dan dua model
lifecycle yang harus dicocokkan. Biaya jembatan itu dibayar **di setiap layar
baru**, bukan sekali di awal. Kita sudah membayarnya empat kali dalam beberapa
hari terakhir — gestur pulau, safe area, tombol back yang artinya berubah,
kepemilikan coordinator.

`NavigationStack` juga punya friksinya sendiri: bug `path`, aturan penempatan
`navigationDestination`, kendali transisi yang terbatas. Bedanya, friksi itu ada
**di dalam satu sistem** dan Apple yang memperbaikinya seiring waktu. Friksi
jembatan permanen karena bentuknya memang begitu.

Itu sebabnya, kalau minimum iOS bisa naik, `NavigationStack` yang menang —
bukan karena lebih canggih hari ini, tapi karena tidak menitipkan utang.

---

## Kenapa

Yang membuat `NavigationView` tidak bisa dipakai bukan "karena SwiftUI",
melainkan karena tumpukannya **tidak bisa dinyatakan sebagai data**. Selection
`Bool`/`Tag` per tautan berarti tumpukan hanya bisa disimpulkan dari tautan mana
yang kebetulan aktif — dari situ lahir `.id()`, penanda dua tahap, dan
destination yang dibekukan.

`NavigationStack` memperbaiki persis itu:

```swift
NavigationStack(path: $path) {
    LandingScreen()
        .navigationDestination(for: TransferRoute.self) { route in
            screen(for: route)
        }
}
```

`path` **adalah** tumpukannya. Semua yang kita bangun di `FlowNavigator` menjadi
operasi array biasa:

| `FlowNavigator` hari ini | `NavigationStack` |
|---|---|
| `push(screen)` | `path.append(route)` |
| `pop()` | `path.removeLast()` |
| `popToRoot()` | `path.removeAll()` |
| `popTo(stepIdentifier:)` | potong array sampai langkah itu |
| `setStack([...])` untuk masuk ke tengah | `path = [langkahA, langkahB]` |

Dan tujuan dibangun **saat di-push**, bukan saat body induk dievaluasi — itu
lazy yang sesungguhnya, tanpa `LazyNavigationLink`.

## Yang bisa dihapus

Kalau pindah ke `NavigationStack`, infrastruktur navigasinya tinggal separuh:

| File | Nasib |
|---|---|
| `FlowNavigationController` | **hilang** — tidak ada `UINavigationController` |
| `FlowStepHostingController` | **hilang** — penanda langkah jadi elemen array |
| `LazyNavigationLink` | **hilang** — kecuali masih ada layar `NavigationView` |
| `FlowPresenter` | **menyusut jadi `.fullScreenCover`** |
| `FlowNavigator` | menyusut jadi pembungkus tipis di atas `path` |
| `AppRouter`, `PendingFlow` | **tetap**, hampir tanpa perubahan |

Yang ikut hilang bersamanya: gestur swipe-back yang harus dikembalikan manual,
perbedaan safe area dan keyboard `UIHostingController` di iOS 13, penelusuran
kedalaman pulau, dan `retainForFlowLifetime`.

## Yang **tidak** berubah

Ini bagian pentingnya, karena menentukan apakah pekerjaan beberapa hari ini
terbuang:

- **Coordinator sebagai objek, bukan `View`.** Tetap benar, dan justru lebih
  cocok — coordinator memegang `path`.
- **`AppRouter` + `PendingFlow` + resolver lintas fitur.** Tidak berubah.
- **Factory per layar, `Routing` sebagai closure.** Tidak berubah.
- **Seluruh perbaikan ViewModel** — `[weak self]`, penerbitan tunggal, cache
  baris, `input` ditulis sekali. Tidak ada hubungannya dengan navigasi.
- **Rencana package.** Tidak berubah; target `Navigation` hanya jadi lebih kecil.

Jadi yang perlu ditulis ulang hanya lapis `FlowNavigator` ke bawah — dan
hasilnya lebih sedikit kode.

---

## Satu konsekuensi desain yang harus diputuskan sekarang

**`path` menyimpan nilai, jadi rute harus `Hashable` — dan sebaiknya value
type.**

`TransferRoute` yang kita buat membawa `TransferLandingUseCase`, sebuah class.
Itu tidak cocok untuk `NavigationStack`: rute yang membawa objek berarti
tumpukannya menyimpan referensi, dan identitas rute jadi bergantung pada
identitas objek.

Bentuk yang benar:

```swift
enum TransferRoute: Hashable {
    case transactionAmount(recipientID: String)
    case bankSummary(bankCode: String)
}
```

Rute membawa **kunci**, bukan objeknya. Coordinator yang memegang UseCase-nya
dan melihatkan datanya saat membangun layar.

Ini sebenarnya perbaikan, bukan sekadar penyesuaian: state flow jadi milik
coordinator, dan tumpukannya jadi data murni yang bisa di-restore, di-log, dan
di-deeplink apa adanya. Tapi itu berarti bentuk `TransferRoute` yang ada
sekarang memang berubah.

---

## Kapan UIKit tetap lebih baik

Jujur, ada empat:

1. **Transisi kustom antar layar.** `NavigationStack` tidak memberi kendali
   sebesar `UIViewControllerAnimatedTransitioning`. Kalau desainnya menuntut
   animasi push khusus, UIKit menang.
2. **Kendali halus atas gestur pop interaktif.** Sama alasannya.
3. **Bercampur dengan view controller UIKit yang sudah ada.** Kalau sebagian
   layar memang UIKit, tumpukan UIKit lebih wajar.
4. **Minimum iOS belum bisa naik.** Ini yang menentukan segalanya.

Kalau keempatnya tidak berlaku, `NavigationStack` yang menang.

---

## Yang perlu diperiksa sebelum memutuskan

**Sebaran versi pengguna Anda.** Ini keputusan bisnis, bukan teknis. Angkanya
ada di App Store Connect — jangan pakai statistik global.

**Versi minimum yang dipilih.** `NavigationStack` ada sejak iOS 16.0, tetapi
banyak laporan bug di 16.0–16.3 — `navigationDestination` yang tidak terpasang
kalau berada di dalam container lazy, dan `path` yang kacau saat pop cepat
berturut-turut. Sebagian besar reda di 16.4. Kalau kebijakan Anda memungkinkan
**iOS 17 sebagai minimum**, itu jauh lebih tenang.

**`navigationDestination` tidak boleh di dalam container lazy.** Ini aturan yang
paling sering menggigit: menaruhnya di dalam `LazyVStack` atau `List` yang
di-scroll membuatnya kadang tidak terdaftar. Taruh di akar layar.

**Satu tipe rute, satu `navigationDestination`.** Dua deklarasi untuk tipe yang
sama di satu tumpukan berperilaku tidak terduga.

---

## Kalau jadi pindah, apa yang dilakukan dengan pekerjaan sekarang

Jangan menulis flow transfer dua kali.

- **Lanjutkan** perbaikan ViewModel, factory, dan `Routing` — semuanya berlaku
  di kedua dunia dan tidak ada yang terbuang.
- **Tunda** memindahkan flow transfer ke `FlowNavigator` versi UIKit kalau
  keputusan `NavigationStack` sudah bulat. Bentuk coordinator-nya sama; yang
  berbeda hanya isi method `push`.
- **Tetap buktikan satu flow lebih dulu**, apa pun alasnya. Alasan langkah itu
  bukan UIKit-nya, melainkan bahwa asumsi tentang navigasi baru terbukti saat
  dijalankan — dan itu berlaku sama untuk `NavigationStack`.

Kalau minimum iOS-nya sudah pasti naik, saya sarankan **langsung ke
`NavigationStack`** dan lewati lapis UIKit sama sekali. Infrastrukturnya lebih
kecil, dan tidak ada jembatan yang harus dirawat selamanya.
