# Aturan Lifecycle

Tujuan dokumen ini satu: membuat kebocoran memori **menggagalkan sesuatu**,
bukan sekadar mencetak sesuatu. Log yang harus dibaca manusia akan luput dalam
dua minggu; yang bertahan adalah aturan yang merahkan CI.

Aturannya berlapis tiga, dari yang paling murah ke paling mahal.

---

## Lapis 1 — Test yang gagal (wajib, berlaku di CI)

**Setiap test yang membuat ViewModel, UseCase, atau Coordinator wajib
memanggil `trackForMemoryLeaks` pada objek tersebut.**

```swift
func testSubmitDoesNotLeak() {
    let useCase = LoginUsernameUseCase()
    let sut = UsernameScreenViewModel()
    sut.setUseCase(useCase)

    trackForMemoryLeaks([sut, useCase])

    sut.submit()
}
```

Ini menangkap retain cycle sungguhan — `[weak self]` yang lupa dipasang di
callback, `sink`, `Timer`, atau observer. Satu baris per objek, dan hasilnya
merah di CI, bukan abu-abu di konsol.

Ini satu-satunya lapis yang bersifat wajib untuk semua perubahan.

---

## Lapis 2 — Probe lifecycle (opt-in, untuk audit)

`LifecycleProbe` dipasang **per class dan sesuai kebutuhan**, tidak di base
class. Pada codebase yang masih punya banyak anomali, memasangnya di base
class menghasilkan ribuan baris yang tidak ada yang baca — dan itu justru
melemahkan aturannya.

Pasang saat:

- Anda sedang menelusuri satu flow yang dicurigai menahan memori.
- Anda menyentuh sebuah layar untuk keperluan lain, dan sekalian
  memasangnya (adopsi bertahap, hanya file yang tersentuh).
- Sebuah layar berat — banyak gambar, list panjang — dan Anda ingin
  memastikan ia benar-benar dilepas.

Pencatatan dan pencetakan dipisah: counter **selalu** jalan, sedangkan konsol
bisa disaring. Default pencetakannya `.all`, jadi memasang probe langsung
terlihat hasilnya tanpa konfigurasi apa pun. Ini aman karena probe opt-in per class — yang tercetak
hanya tipe yang sengaja dipasangi.

```swift
// AppDelegate, hanya untuk build DEBUG
#if DEBUG
LifecycleTracker.shared.loggingPolicy = .matching(["DebitCard"])  // saring
LifecycleTracker.shared.loggingPolicy = .none                     // bungkam
#endif
```

Turunkan hanya kalau konsolnya sudah benar-benar ramai. Counter tetap akurat
apa pun pilihannya, jadi checkpoint di Lapis 3 tidak terpengaruh.

---

## Lapis 3 — Checkpoint navigasi (wajib untuk perubahan navigasi)

Log berjalan menjawab "apa yang terjadi". Checkpoint menjawab "apakah sudah
bersih", dan itu pertanyaan yang jauh lebih berguna.

**Prosedur, sebelum me-merge perubahan apa pun pada coordinator atau
navigasi:**

1. Jalankan flow terdalam yang tersentuh perubahan, dari root sampai layar
   terakhir.
2. Kembali ke root.
3. Baca hasilnya:

```swift
print(LifecycleTracker.shared.snapshotDescription())
```

Sambungkan ini ke debug menu supaya tidak perlu breakpoint.

**Lulus** berarti tidak ada tipe berumur layar yang tersisa hidup setelah
kembali ke root. Nilai `peak` di ringkasan juga memberi tahu apakah memori
tumbuh mengikuti kedalaman navigasi — kalau puncaknya sama dengan jumlah layar
yang dilewati, objek memang tertahan sepanjang jalur.

Keluarannya kira-kira begini:

```
[LIFECYCLE] Still alive:
  2x DetailCardInfoScreenUseCase (peak 3)
  1x DetailCardInfoScreenViewModel (peak 3)
```

Seluruh pesan runtime — log, assertion, dan pesan kegagalan test — memakai
bahasa Inggris supaya bisa ditempel apa adanya ke issue, PR, atau percakapan
dengan pihak lain. Komentar dan dokumen tetap bahasa Indonesia.

Kalau ada yang tersisa, `liveInstanceIdentifiers(of:)` memberi alamat objeknya
dalam hex, dan alamat itu bisa dicari langsung di Memory Graph Debugger untuk
melihat siapa yang menahannya.

### Cara membaca snapshot-nya

`snapshotDescription()` hanya **mengembalikan** `String`. Memanggilnya tanpa ada
yang mencetak hasilnya tidak menghasilkan apa pun yang terlihat. Ada tiga jalan,
urut dari yang paling tidak merepotkan:

**1. Lewat log yang sudah Anda baca.** `logSnapshot()` mengirimnya ke subsystem,
kategori, dan level yang sama dengan INIT/DEINIT. Kalau log INIT terlihat, ini
terlihat juga. Pasang pemicunya di satu tempat yang mudah dijangkau — misalnya
di `AppDelegate`:

```swift
#if DEBUG
func applicationDidEnterBackground(_ application: UIApplication) {
    LifecycleTracker.shared.logSnapshot()
}
#endif
```

Lalu: masuk ke layar dalam, kembali ke root, tekan tombol home. Snapshot-nya
muncul di log, berisi apa saja yang masih hidup padahal seharusnya sudah lepas.

**2. Lewat debugger, tanpa mengubah kode sama sekali.** Jalankan dari Xcode,
tekan tombol pause (⌃⌘Y), lalu di konsol debugger:

```
expression -l Swift -- print(LifecycleTracker.shared.snapshotDescription())
```

**3. Lewat clipboard, kalau tidak ada konsol sama sekali.**
`copySnapshotToPasteboard()` menyalin snapshot supaya bisa ditempel ke catatan
atau chat. Ini untuk aplikasi yang terpasang di device tanpa Xcode menempel.
Pasang pemicunya di gestur yang tidak dipakai, misalnya long-press pada judul
navigation bar layar root.

---

## Cara membaca hasilnya

Tidak semua objek yang bertahan setelah pop adalah kebocoran. Ada tiga pola,
dan hanya satu yang benar-benar bug:

| Pola | Artinya | Tindakan |
|---|---|---|
| Deinit saat pop | Sehat | — |
| Deinit tertunda: baru lepas saat naik lebih tinggi, atau saat layar yang sama dibuka lagi | Pelepasan tertunda, bukan kebocoran. Batas atasnya adalah jalur terdalam yang pernah dikunjungi | Ukur dampaknya di Memory Report. Tangani kalau layarnya berat |
| Tidak pernah deinit, bahkan setelah kembali ke root | Retain cycle **atau** layarnya di-cache — lihat di bawah | Bedakan dulu, jangan langsung cari `weak` yang lupa |

Pembedaan ini penting: menghabiskan waktu mengejar pola kedua seperti mengejar
bug padahal ia perilaku wajar `NavigationView` akan membuang banyak waktu.

### Kalau yang tercatat hanya INIT, DEINIT tidak pernah

Ada dua sebab yang gejalanya sama persis di log, tetapi penanganannya
berlawanan. Bedakan dulu dengan satu percobaan: **masuk ke layar itu, kembali,
masuk lagi, tiga kali.**

| Yang terlihat di log | Artinya |
|---|---|
| `INIT` hanya **satu kali** untuk tiga kali masuk | Objeknya tidak dibangun ulang — ada yang men-cache layarnya. Bukan cycle. Memorinya berbatas satu instance, tetapi state layarnya ikut basi: scroll, kata kunci, dan isi list masih yang lama saat masuk kembali |
| `INIT` **tiga kali**, `DEINIT` nol | Objeknya menumpuk. Ini retain cycle, dan seharusnya tertangkap Lapis 1 |

Penanda tambahan untuk yang pertama, tanpa melihat log sama sekali: scroll ke
bawah, tekan back, masuk lagi. Kalau posisi scroll dan hasil pencariannya masih
persis seperti sebelum keluar, layarnya memang di-cache.

Satu sumber cache seperti itu pernah ada di template ini: `LazyNavigationLink`
menyimpan hasil build destination di `lazy var` yang tidak bisa dikosongkan
lagi. Struct layar tujuan memegang ViewModel-nya lewat `@ObservedObject`, dan
storage-nya dipegang `@State` di dalam tautan — sedangkan tautannya ada di body
layar **induk** selama layar induk hidup. Jadi umur ViewModel tujuan mengikuti
umur layar induk, dan untuk flow yang berangkat dari root, itu berarti tidak
pernah dilepas. Sudah ditutup: cache-nya dilepas begitu selection tautannya
tidak lagi menunjuk ke sana.

---

## Catatan metodologi

Probe hanya hidup di build **Debug**, dan Debug tidak mengoptimalkan ARC.
Umur objek di sana bisa terlihat **lebih panjang** daripada di Release. Untuk
keputusan memori yang serius, konfirmasi temuannya di build Release dengan
Instruments (Allocations dan Leaks). Debug cocok untuk menemukan tersangka,
tidak cocok untuk menjadi bukti akhir.

---

## Ringkasan untuk PR

- [ ] Test baru memanggil `trackForMemoryLeaks` pada ViewModel/UseCase/Coordinator
- [ ] Perubahan navigasi sudah lewat checkpoint Lapis 3
- [ ] Tidak ada `assign(to:on:)` baru (SwiftLint akan menolaknya)
- [ ] Closure yang disimpan memakai `[weak self]`
