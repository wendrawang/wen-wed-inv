# Urutan modernisasi

Lima pekerjaan sedang ingin dikerjakan bersamaan: pemecahan ke local SPM,
`async/await`, `Codable`, perbaikan kebocoran, dan migrasi navigasi. Dokumen ini
memisahkannya supaya ada yang bisa dimulai besok pagi.

---

## Aturan yang menyelesaikan sebagian besar kebingungan

Bagi setiap pekerjaan menjadi dua jenis:

**Sempit** — menyentuh satu file atau satu layar, diverifikasi kompiler atau
test, bisa dibatalkan sendirian.

**Lebar** — mengubah batas atau kontrak yang dipakai banyak tempat sekaligus.

> **Kerjakan pekerjaan lebar satu per satu. Pekerjaan sempit boleh berapa pun,
> kapan pun, oleh siapa pun.**

Kenapa ini yang menentukan: kalau dua pekerjaan lebar berjalan bersamaan, setiap
kegagalan build punya dua kemungkinan sebab, dan waktu habis untuk memilah, bukan
memperbaiki. Anda sudah merasakannya minggu ini dengan navigasi — satu perubahan
lebar saja sudah menghabiskan empat percobaan.

| Pekerjaan | Jenis |
|---|---|
| Perbaikan kebocoran per layar | **sempit** |
| `Codable` per endpoint | **sempit** |
| Mengeluarkan factory per layar | **sempit** |
| `async/await` **di lapis service** | **sempit** |
| Migrasi flow transfer | lebar |
| Merapikan folder lapis bersama | lebar |
| Membuat package pertama | lebar |
| Mengganti kontrak UseCase ke `async` | **lebar, dan paling berisiko** |

---

## Yang bisa dimulai besok, tanpa menunggu apa pun

Ketiganya sempit, jadi boleh jalan paralel dan tidak perlu koordinasi:

**1. Setiap layar yang kebetulan disentuh, dirapikan sekalian.**
`[weak self]` di closure yang disimpan, penerbitan tunggal untuk list, `input`
ditulis sekali, dan satu test `trackForMemoryLeaks`. Aturannya ada di
[SCREEN_PATTERN.md](SCREEN_PATTERN.md).

Ini yang paling menguntungkan per jam kerja, dan **tidak bergantung pada satu
pun keputusan lain**. Kalau semua yang lain tertunda setahun, ini tetap layak.

**2. `Codable` di endpoint yang kebetulan disentuh.** Per endpoint, bukan per
proyek. DTO baru di sebelah yang lama, dipakai satu tempat, yang lama dihapus
saat sudah tidak ada yang memanggil.

**3. `async/await` — tapi dari bawah, bukan dari atas.** Bagian berikutnya.

---

## `async/await` tanpa menyentuh satu pun ViewModel

Ini yang paling sering dikerjakan terbalik, dan terbaliknya mahal.

Arsitektur Anda berbasis callback: `useCase.callback.onFetchSucceed`. Mengubah
kontrak itu menjadi `async` berarti menyentuh **setiap** UseCase dan setiap
ViewModel sekaligus — pekerjaan lebar terbesar dari semuanya, dan tidak memberi
manfaat apa pun sampai selesai.

Yang benar: adopsi dari **lapis service**, di balik API callback yang sudah ada.

```swift
// Service — bentuk barunya
func fetchRecipients(page: Int) async throws -> [BankContact]

// UseCase — kontraknya tidak berubah sedikit pun
func loadData(pageNumber: Int, searchKeyword: String) {
    Task { [weak self] in
        do {
            let contacts = try await service.fetchRecipients(page: pageNumber)
            await MainActor.run { self?.handleFetchSucceed(contacts) }
        } catch {
            await MainActor.run { self?.handleFetchFailed(error) }
        }
    }
}
```

ViewModel tidak tahu apa-apa. Layar tidak tahu apa-apa. Yang berubah satu file.

Keuntungannya langsung terasa: rantai closure bertingkat hilang, penanganan
error jadi satu `catch`, dan `await MainActor.run` membuat jaminan main thread
jadi eksplisit — persoalan yang sudah kita temui di `callback.onStartFetchLoading`.

`async/await` bisa dipakai di iOS 13 sejak Xcode 13.2, jadi keputusan minimum
iOS tidak menghalangi.

**Mengganti kontrak UseCase menjadi `async` ditunda** sampai batas package
stabil. Kalau nanti dikerjakan, per fitur, bukan sekaligus.

---

## Pekerjaan lebar, satu per satu

### Lebar 1 — buktikan flow transfer (sedang berjalan)

Selesai kalau: daftar muncul, tab dan pencarian bekerja, back kembali ke
Dashboard, dan probe mencetak INIT/DEINIT berpasangan.

Ini yang paling kecil dari semua pekerjaan lebar, dan ia menjawab pertanyaan
yang menghalangi sisanya. **Jangan memulai apa pun yang lebar sebelum ini
hijau.**

### Lebar 2 — merapikan folder, masih di dalam satu target

Lapis 1–3 di [SHARED_CODE_LAYERS.md](SHARED_CODE_LAYERS.md): token, tipe dan
extension murni, konstanta domain.

**Belum ada `Package.swift`.** Ini murni pemindahan folder — tidak ada `public`,
tidak ada resource yang pindah bundle, tidak ada build setting. Justru itu yang
membuatnya murah, dan itu alasan mengerjakannya sebelum package.

Selesai kalau: susunannya rapi dan tidak ada yang melingkar. Kalau ada file yang
tidak jelas masuk mana, itu tanda file-nya mengerjakan dua hal — pecah dulu.

### Lebar 3 — package pertama, isinya `Navigation` saja

Satu target. Buktikan aplikasi build dan flow transfer masih jalan.

Sengaja `Navigation` karena dependensinya nol, jadi kalau ada yang tidak beres,
sebabnya pasti setup SPM — bukan kode Anda.

Selesai kalau: project build dan tidak ada satu baris pun flow lama yang berubah.

### Lebar 4 — target berikutnya, satu per satu

`Core`, lalu `DesignSystem`, lalu `Domain`. Masing-masing satu langkah
tersendiri, masing-masing bisa dibatalkan sendirian.

### Lebar 5 — fitur pertama jadi package

Transfer, karena ia sudah paling rapi. Di sini `R.swift` per-module dan
`Bundle.module` baru menggigit — lihat [MODULARIZATION.md](MODULARIZATION.md).

---

## Kalau harus memilih satu hal saja

**Perbaikan kebocoran, dikerjakan sambil jalan di layar mana pun yang disentuh.**

Ia satu-satunya yang tidak bergantung pada keputusan apa pun, memberi hasil
sejak hari pertama, dan tidak ada satu pun skenario di mana pekerjaannya
terbuang. Sisanya bisa menunggu; ini tidak perlu.

---

## Yang sebaiknya tidak dilakukan

- **Memulai package sebelum foldernya rapi.** Batas package akan memotong di
  tempat yang salah, dan memperbaikinya jauh lebih mahal setelah ada
  `public` di mana-mana.
- **Mengganti kontrak UseCase ke `async` bersamaan dengan pemecahan package.**
  Setiap error punya dua kemungkinan sebab.
- **Memindahkan `Screen` dan `ScreenContentViewModel` lebih awal.** Keduanya
  menyebut semua lapis sekaligus; memindahkannya duluan menyeret seluruh
  aplikasi dan menyenggol setiap flow lama.
- **Mengerjakan satu teknik ke seluruh aplikasi.** Untuk aplikasi sebesar ini,
  selesaikan **satu fitur secara utuh** dulu sebagai rujukan, baru sebarkan.
  Transfer sudah setengah jalan ke sana.
