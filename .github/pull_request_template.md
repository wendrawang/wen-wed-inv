## Ringkasan

<!-- Apa yang berubah dan kenapa. -->

## Lifecycle

Detail lengkap ada di [docs/LIFECYCLE_RULES.md](../docs/LIFECYCLE_RULES.md).

- [ ] Test baru memanggil `trackForMemoryLeaks` pada ViewModel / UseCase / Coordinator yang dibuatnya
- [ ] Closure yang disimpan (callback, `sink`, `Timer`, observer) memakai `[weak self]`
- [ ] Tidak ada `assign(to:on:)` baru

## Navigasi

Isi bagian ini hanya kalau PR menyentuh coordinator atau navigasi.

- [ ] Sudah dijalankan checkpoint: masuk ke layar terdalam, kembali ke root, lalu `LifecycleTracker.shared.snapshotDescription()`
- [ ] Tidak ada tipe berumur layar yang tersisa hidup di root

Hasil checkpoint:

```
<!-- tempel keluaran snapshotDescription() di sini -->
```

## Performa

- [ ] Tidak ada kerja berat baru di dalam `body` (formatting, sorting, decoding, pembuatan formatter)
- [ ] Tidak ada `AnyView` baru di jalur yang sering render
