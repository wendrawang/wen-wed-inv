#if DEBUG

import Foundation

/// Menghitung berapa kali `body` sebuah view dievaluasi.
///
/// Ini alat ukur sementara, bukan bagian permanen dari kode. Pasang saat
/// menyelidiki satu layar, baca angkanya, lalu **lepas lagi**.
///
/// ## Kenapa ini ada, padahal Instruments punya template SwiftUI
///
/// Instrument "View Body" hanya tersedia pada versi iOS yang cukup baru. Kalau
/// perangkat tes Anda tidak memenuhi syaratnya — atau Anda ingin membandingkan
/// perilaku pada iOS lama yang justru jadi target minimum — penghitung ini
/// bekerja di mana saja dan angkanya sama-sama bisa dibandingkan sebelum dan
/// sesudah perubahan.
///
/// ## Cara memakainya
///
/// Letakkan panggilannya sebagai **pernyataan pertama** di dalam `body`, lalu
/// beri `return` eksplisit pada sisanya:
///
///     var body: some View {
///         #if DEBUG
///         RenderCounter.shared.record("DetailCardInfoScreen")
///         #endif
///
///         return ZStack {
///             renderNavigationLinks()
///             render()
///         }
///     }
///
/// Bentuk ini dipilih dengan sengaja. Membungkus penghitung dalam view kecil
/// seperti `RenderProbe()` terlihat lebih rapi tetapi **tidak dapat
/// dipercaya**: kalau nilai propertinya tidak berubah, SwiftUI boleh melewati
/// evaluasi body-nya sehingga hitungannya kurang dari yang sebenarnya.
///
/// Ya, ini efek samping di dalam `body` — hal yang justru dilarang di
/// SCREEN_PATTERN.md. Bedanya, ini hanya menaikkan penghitung dan tidak pernah
/// menyentuh state yang diamati SwiftUI, jadi ia tidak memicu invalidasi dan
/// tidak mengubah apa yang sedang diukur. Tetap saja: lepas setelah selesai.
final class RenderCounter {

    static let shared = RenderCounter()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var startedAt = Date()

    private init() {}

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }

        counts[name] = (counts[name] ?? 0) + 1
    }

    /// Panggil tepat sebelum memulai interaksi yang diukur — misalnya sesaat
    /// sebelum mulai men-scroll.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        counts.removeAll()
        startedAt = Date()
    }

    /// Panggil tepat setelah interaksi selesai.
    ///
    /// Angka per detik lebih berguna daripada jumlah mentah, karena durasi
    /// scroll manual tidak pernah sama persis antar percobaan.
    func report() -> String {
        lock.lock()
        defer { lock.unlock() }

        guard !counts.isEmpty else {
            return "[RENDER] No body evaluations recorded."
        }

        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)

        let rows = counts
            .sorted { $0.value > $1.value }
            .map { name, count in
                let perSecond = Double(count) / elapsed
                return String(
                    format: "  %6d  %7.1f/s  %@",
                    count,
                    perSecond,
                    name
                )
            }
            .joined(separator: "\n")

        return String(
            format: "[RENDER] %.1fs elapsed\n%@",
            elapsed,
            rows
        )
    }
}

#endif
