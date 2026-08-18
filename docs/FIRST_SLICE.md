# Irisan pertama

Kalau hanya satu dokumen yang sempat dibaca, ini. Sisanya rujukan saat
dibutuhkan, bukan bacaan wajib.

---

## Kenapa rencana sebelumnya terasa terlalu besar

Karena semuanya **horizontal** — "semua service jadi `Codable`", "semua konstanta
naik ke Core", "semua layar dirapikan". Pekerjaan horizontal punya dua sifat yang
membuatnya melelahkan:

- Tidak ada titik selesai yang jelas. Selalu ada satu file lagi.
- Tidak ada yang bisa dirilis di tengah jalan. Bulan ketiga terlihat sama dengan
  bulan pertama.

Revamp yang berhasil berbentuk **irisan vertikal**: satu layar, dari DTO sampai
tampilan, ditulis dengan aturan baru, lalu **dirilis**. Setelah itu semuanya
tinggal pengulangan.

---

## Irisan pertama: satu layar kecil yang hanya membaca

Pilih satu layar dengan empat sifat:

1. **Read-only.** Tidak memindahkan uang. Kalau salah, tidak ada yang rugi.
2. **Satu endpoint.** Cukup untuk membuktikan `Codable` dan `async/await`.
3. **Daun.** Tidak bercabang ke layar lain — jadi navigasi tidak ikut terlibat.
4. **Kecil.** Kalau butuh lebih dari seminggu, pilih yang lain.

Kandidat yang biasanya cocok: satu layar di tab **More**, detail sebuah kartu,
atau daftar riwayat sederhana.

**Layar ini tidak butuh revamp navigasi sama sekali.** Ia dibuka coordinator
lama yang sudah ada. Dua pekerjaan itu memang tidak perlu diurutkan terhadap satu
sama lain, dan itu yang membuat irisan pertama jauh lebih ringan daripada
kelihatannya.

---

## Isi irisannya

Lima hal, semuanya untuk satu layar itu saja.

### 1. Package, dengan satu target

```
Packages/
  Platform/
    Package.swift
    Sources/Core/          isinya hanya yang dibutuhkan layar ini
```

Jangan memindahkan `Constants` atau `Extensions` sekarang. Hanya yang benar
benar dipakai layar ini yang ikut. Kalau ternyata tidak ada, `Core` boleh kosong
dulu.

### 2. DTO `Codable` — satu endpoint

```swift
struct RewardListResponse: Decodable {
    let items: [RewardItemResponse]
}
```

DTO baru di sebelah yang lama. Yang lama tidak disentuh dan tidak dihapus.

### 3. Protokol service di package, implementasi tetap di project

```swift
// package
public protocol RewardFetching {
    func fetchRewards() async throws -> [Reward]
}
```

```swift
// project — Alamofire, header, session, semuanya tetap di sini
extension RewardService: RewardFetching {}
```

Tidak ada satu baris kode networking yang dipindah. `async/await` masuk di sini,
di kode baru — bukan dengan mengubah yang lama.

### 4. ViewModel dengan aturan yang sudah kita sepakati

`[weak self]` di closure yang disimpan, `input` ditulis sekali, penerbitan
tunggal kalau ada list, dan satu test:

```swift
func testViewModelIsReleased() {
    let sut = RewardListFactory(fetching: FakeRewardFetching()).createViewModel()
    trackForMemoryLeaks(sut)
}
```

Test itu jalan tanpa jaringan, karena service-nya sudah berupa protokol.

### 5. Coordinator lama membukanya

```swift
// di coordinator yang sudah ada, tidak berubah bentuknya
RewardListFactory(fetching: RewardService()).createScreen()
```

---

## Selesai kalau

- Layarnya jalan di aplikasi dan **masuk rilis berikutnya**
- Test kebocorannya hijau di CI
- Tidak ada satu baris pun layar lain yang berubah

Kalau ketiganya terpenuhi, Anda punya rujukan yang bisa disalin — dan
pertanyaan "mulai dari mana" tidak akan muncul lagi, karena jawabannya jadi
"irisan berikutnya".

---

## Irisan berikutnya, dan seterusnya

Urutannya menambah **satu** hal baru tiap kali. Jangan dua.

| Irisan | Tambahannya |
|---|---|
| 1 | package + `Codable` + `async` + aturan ViewModel — satu layar daun |
| 2 | layar yang punya list dan pagination |
| 3 | layar yang bercabang → di sini navigasi flow baru masuk |
| 4 | satu fitur utuh jadi package sendiri |
| 5 | `Screen`/`ScreenContentViewModel` versi baru, saat sudah jelas bentuknya |

Yang di baris 5 sengaja terakhir. Bentuk base yang benar baru kelihatan setelah
empat irisan — menebaknya di awal berarti menebak, dan menebak base berarti
seluruh aplikasi ikut menanggung tebakannya.

---

## Yang jangan dikerjakan sekarang

- **Mengosongkan project atau memindahkan seluruh folder.** Belum ada yang bisa
  dinilai dari situ.
- **Mengubah `Screen` atau `ScreenContentViewModel`.** Menyeret semua flow lama.
- **Mengganti seluruh service ke `Codable` sekaligus.** Horizontal — tidak ada
  yang bisa dirilis di tengahnya.
- **Menunggu pemecahan package selesai untuk mulai merapikan layar.** Perbaikan
  kebocoran tidak bergantung pada apa pun; kerjakan sambil jalan di layar mana
  pun yang kebetulan disentuh.
