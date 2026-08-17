# Panduan Pengukuran

Semua yang tersisa di [STATUS.md](STATUS.md) bagian "Masih dugaan" hanya bisa
dimajukan dengan angka. Dokumen ini cara mendapatkannya.

---

## Aturan dasar

Empat hal ini menentukan apakah hasilnya bisa dipercaya. Melewatkan salah satu
membuat sisanya sia-sia.

**Perangkat fisik, bukan simulator.** Simulator memakai GPU Mac dan tidak
punya batasan memori maupun thermal yang sama. Angkanya tidak berarti apa-apa
untuk keputusan performa.

**Build Release.** Di Xcode: Edit Scheme → Profile → Build Configuration =
Release. Build Debug tidak mengoptimalkan ARC maupun kode Swift, dan bisa
berbeda beberapa kali lipat.

**Ambil baseline dulu, sebelum mengubah apa pun.** Ini yang paling sering
dilewatkan. Tanpa angka "sebelum", angka "sesudah" tidak bisa dibaca — Anda
hanya akan tahu berapa nilainya, bukan apakah perubahan Anda membantu.

**Ulangi tiga kali, ambil nilai tengah.** Interaksi manual tidak pernah sama
persis. Sekali jalan tidak cukup untuk membedakan perbaikan 20% dari derau.

Satu lagi: buang percobaan pertama setelah aplikasi baru dipasang. Peluncuran
pertama membawa kerja tambahan yang bukan bagian dari yang Anda ukur.

---

## Ukuran 1 — Berapa kali `body` dievaluasi

Menjawab dugaan terkuat kita: apakah `scrollViewContainerSize` dan
`scrollViewContentSize` sebagai `@Published` membuat seluruh layar
di-invalidasi setiap frame scroll.

### Di `body` yang mana?

Ada beberapa `body` yang bertumpuk — coordinator, `LazyNavigationLink`,
`LazyNavigationDestination`, `Screen`, lalu layar itu sendiri. Yang relevan
hanya yang **mengamati `ScreenContentViewModel`**, karena di situlah dua
property `CGSize` itu berada:

| `body` | Mengamati? |
|---|---|
| Coordinator | Tidak |
| `LazyNavigationLink` / `LazyNavigationDestination` | Tidak |
| `Screen` | **Ya** — `@ObservedObject private var contentViewModel` |
| Layar (mis. `DetailCardInfoScreen`) | **Ya** — `@ObservedObject var viewModel`, objek yang sama |

Jadi satu penulisan ke `scrollViewContentSize` meng-invalidasi **dua** body
sekaligus. Coordinator dan pembungkus lazy tidak ikut, karena mereka tidak
mengamati objek itu — itu justru bukti bahwa `LazyNavigationLink` sudah bekerja.

### Jalur cepat: `RenderCounter`

Bekerja di semua versi iOS dan tidak butuh Instruments sama sekali.

**Pasang di `Screen`, bukan di layar satu per satu.** `Screen` generik terhadap
`Content`, jadi satu pemasangan otomatis memberi label per tipe layar dan
langsung mencakup seluruh aplikasi:

```swift
var body: some View {
    #if DEBUG
    RenderCounter.shared.record(String(describing: Content.self))
    #endif

    return Group {
        if #available(iOS 15.0, *) {
            render().dynamicTypeSize(.large)
        } else {
            render().environment(\.sizeCategory, .large)
        }
    }
}
```

Perhatikan `Group`-nya. Menambahkan pernyataan sebelum `if` membuat `body`
berhenti jadi `@ViewBuilder` implisit, dan dua cabang `if #available`
menghasilkan tipe berbeda. `Group` menyatukannya tanpa perlu `AnyView` — yang
penting, karena `AnyView` justru akan mengubah perilaku yang sedang diukur.

Kalau ingin memisahkan berapa yang datang dari `Screen` dan berapa dari layar
di dalamnya, pasang juga di layar yang bersangkutan:

```swift
var body: some View {
    #if DEBUG
    RenderCounter.shared.record("DetailCardInfoScreen")
    #endif

    return ZStack {
        renderNavigationLinks()
        render()
    }
}
```

Lalu dari debug menu:

1. `RenderCounter.shared.reset()`
2. Scroll dengan kecepatan sedang selama ±10 detik
3. `print(RenderCounter.shared.report())`

Keluarannya:

```
[RENDER] 10.2s elapsed
    612    60.0/s  DetailCardInfoScreen
```

**Cara membacanya.** Angka yang mendekati laju refresh layar — sekitar 60/detik,
atau 120/detik di perangkat ProMotion — berarti seluruh body dievaluasi ulang
setiap frame. Itu mengonfirmasi dugaannya. Angka di bawah 5/detik berarti
invalidasinya sudah wajar dan penyebab fps ada di tempat lain.

Setelah itu pasang penjagaan nilai pada kedua property `CGSize` (bentuknya ada
di [BASE_VIEWMODEL_FINDINGS.md](BASE_VIEWMODEL_FINDINGS.md) temuan 2), lalu
ulangi persis langkah yang sama. Kalau angkanya turun drastis, terkonfirmasi.

### Jalur Instruments

Kalau perangkat tes Anda cukup baru, template **SwiftUI** memberi rincian per
tipe view tanpa perlu menempel kode.

1. Product → Profile (⌘I)
2. Pilih template **SwiftUI**
3. Rekam, buka layar, scroll ±10 detik, hentikan
4. Lihat track **View Body**

Yang dicari: tipe view mana yang jumlah evaluasinya paling tinggi, dan berapa
total waktu yang dihabiskannya. Kelebihannya dibanding `RenderCounter` — ia
menunjukkan *view mana* yang paling boros, bukan cuma layar secara keseluruhan.

Catatan: kalau Anda profiling di iOS versi baru sementara target minimum Anda
iOS 13, perilaku invalidasinya bisa sedikit berbeda. Untuk pertanyaan
"berapa kali", perbedaannya tidak material.

---

## Ukuran 2 — Apakah scroll benar-benar tersendat

Jumlah evaluasi body itu penyebab; yang dirasakan pengguna adalah hitch.
Keduanya perlu diukur karena tidak selalu berbanding lurus.

1. Product → Profile
2. Template **Animation Hitches**
3. Rekam, scroll layar yang sama, hentikan

Yang dibaca: **hitch time ratio**, dalam milidetik hitch per detik. Di bawah
5 ms/s umumnya tidak terasa; di atas 10 ms/s sudah terlihat sebagai patah-patah.

Ukur ini **sebelum dan sesudah** perubahan yang sama seperti Ukuran 1. Kalau
jumlah body turun tapi hitch tidak berubah, berarti penyebab sebenarnya bukan
invalidasi — dan itu temuan yang sama berharganya.

---

## Ukuran 3 — `.blur()` di akar setiap layar

Jangan mencoba memvisualisasikan offscreen rendering. Cara paling langsung dan
paling jujur adalah A/B.

1. Ukur hitch ratio dengan Ukuran 2, catat.
2. Komentari seluruh modifier `.blur(...)` di `render()`.
3. Ukur lagi dengan interaksi yang sama persis.

Kalau angkanya tidak berubah, SwiftUI memang memotong jalur itu saat radiusnya
nol dan dugaan ini dicoret. Kalau turun, blur-nya nyata berbiaya dan layak
diganti dengan bentuk yang benar-benar tidak memasang modifier saat tidak
dipakai.

Sebagai pemeriksaan visual cepat, Simulator punya Debug → Color Off-screen
Rendered. Perenderan simulator berbeda dari perangkat, jadi pakai itu untuk
menemukan *di mana* offscreen terjadi, bukan untuk memutuskan seberapa mahal.

---

## Ukuran 4 — Memori dan pelepasan tertunda

Menjawab: apakah pelepasan tertunda yang sudah kita catat benar-benar
membebani, atau cuma kerapian.

1. Product → Profile
2. Template **Allocations**
3. Rekam, biarkan aplikasi diam di root beberapa detik
4. Tekan **Mark Generation**
5. Masuk ke flow terdalam, kembali ke root
6. Tekan **Mark Generation** lagi

Yang dibaca: kolom **Persistent Bytes** pada generasi kedua. Itu memori yang
masih tertahan setelah kembali ke root. Ulangi maju-mundur beberapa kali —
kalau angkanya terus naik tanpa pernah turun, itu kebocoran; kalau naik lalu
datar, itu pelepasan tertunda yang batasnya jelas.

Untuk pembacaan cepat tanpa Instruments, Memory Report di Xcode sudah cukup
untuk melihat apakah tren memori naik terus atau datar.

---

## Memilih layar yang diukur

Dugaan soal ukuran scroll hanya bisa diuji di layar yang **benar-benar
di-scroll**. Pada layar pendek seperti Detail Card Info, kedua property `CGSize`
itu praktis tidak pernah berubah, jadi hasilnya akan bersih dan tidak
membuktikan apa pun.

Yang dicari: konten panjang yang butuh scroll jauh, idealnya berisi banyak baris
dan gambar. Di aplikasi seperti ini biasanya riwayat transaksi, daftar kartu,
atau dashboard. Layar seperti itu juga membawa persoalan yang tidak dimiliki
layar pendek — iOS 13 tidak punya `LazyVStack`, jadi `ScrollView` + `VStack`
membangun seluruh isinya sekaligus — sehingga kalau memang ada masalah fps,
di sanalah ia paling mungkin terlihat.

## Ukur dulu, migrasi belakangan

Godaan yang wajar: sekalian saja migrasikan layar itu ke pola baru sambil
mengukurnya. **Jangan.**

Baseline harus diambil dari kode yang sekarang. Kalau layarnya dimigrasi lalu
diukur, dan angkanya membaik, Anda tidak akan tahu apakah itu karena migrasinya
atau karena penjagaan nilai pada dua property `CGSize` — padahal yang kedua ada
di base class dan menguntungkan **semua** layar tanpa migrasi apa pun.

Urutannya:

1. Pasang `RenderCounter` di `Screen`. Tidak mengubah perilaku apa pun.
2. Ukur layar panjang itu apa adanya. Ini baseline.
3. Pasang penjagaan nilai pada dua property `CGSize` di base. **Hanya itu.**
4. Ukur lagi, layar dan interaksi yang sama persis.

Selisih antara langkah 2 dan 4 adalah efek murni dari satu perubahan. Migrasi
layar itu ke pola baru adalah pekerjaan terpisah setelahnya, dengan
pengukurannya sendiri.

## Urutan yang disarankan

1. **Ukuran 1 jalur cepat** pada layar terpanjang. Paling murah, dan menjawab
   dugaan terkuat kita.
2. Kalau angkanya tinggi: pasang penjagaan nilai, ukur lagi, lalu **Ukuran 2**
   untuk memastikan pengguna benar-benar merasakan bedanya.
3. **Ukuran 3** hanya kalau Ukuran 2 masih menunjukkan hitch setelah Ukuran 1
   beres.
4. **Ukuran 4** kapan saja — tidak bergantung pada yang lain.

Yang perlu dicatat setiap kali: nama perangkat, versi iOS, konfigurasi build,
dan interaksi persisnya. Tanpa itu, angka dari dua hari yang lalu tidak bisa
dibandingkan dengan angka hari ini.
