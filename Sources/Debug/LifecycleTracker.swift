#if DEBUG

import Foundation
import os.log

/// Menentukan tipe mana yang boleh mencetak ke konsol.
///
/// Kebijakan ini **hanya mengatur pencetakan**, tidak pernah mengatur
/// pencatatan. Counter selalu akurat apa pun pilihan di sini, sehingga
/// checkpoint (lihat `liveTypes()`) tetap bisa dipercaya walaupun konsol
/// sedang dibungkam.
enum LifecycleLoggingPolicy {
    /// Cetak semua. Nyaman saat mengaudit satu flow, berisik di app besar.
    case all

    /// Jangan cetak apa pun. Counter tetap jalan; pakai checkpoint untuk
    /// membaca hasilnya. Ini pilihan yang tepat untuk pemakaian sehari-hari
    /// pada codebase yang masih banyak anomali.
    case none

    /// Cetak hanya tipe yang namanya mengandung salah satu kata kunci ini.
    /// Contoh: `.matching(["DebitCard", "Login"])` saat mengaudit dua flow.
    case matching([String])

    func allows(_ typeName: String) -> Bool {
        switch self {
        case .all:
            return true

        case .none:
            return false

        case .matching(let keywords):
            return keywords.contains { typeName.contains($0) }
        }
    }
}

/// Menghitung berapa objek dari tiap tipe yang sedang hidup.
///
/// Ada dua cara memakainya, dan yang kedua jauh lebih berguna sebagai rule
/// tim daripada yang pertama:
///
/// 1. Membaca log berjalan — berguna saat menelusuri satu kasus.
/// 2. **Checkpoint** — kembali ke root, lalu tanya tipe apa yang masih hidup.
///    Ini mengubah "silakan baca log" menjadi pertanyaan berjawaban ya/tidak.
final class LifecycleTracker {

    static let shared = LifecycleTracker()

    /// Atur sekali di awal aplikasi, misalnya di `AppDelegate`.
    /// Default `.none` supaya memasang probe tidak pernah membanjiri konsol
    /// orang lain; naikkan ke `.matching([...])` saat Anda sedang mengaudit.
    var loggingPolicy: LifecycleLoggingPolicy = .none

    private let lock = NSLock()

    private let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "Application",
        category: "ObjectLifecycle"
    )

    /// Identifier instance yang sedang hidup, per nama tipe.
    private var liveInstances: [String: Set<String>] = [:]

    /// Jumlah tertinggi yang pernah hidup bersamaan, per nama tipe.
    /// Berguna untuk menjawab "apakah memori tumbuh mengikuti kedalaman
    /// navigasi" tanpa perlu membuka Instruments.
    private var peakCounts: [String: Int] = [:]

    private init() {}

    // MARK: - Pencatatan

    func recordInitialization(
        typeName: String,
        instanceIdentifier: String
    ) {
        lock.lock()

        var instances = liveInstances[typeName] ?? []
        instances.insert(instanceIdentifier)
        liveInstances[typeName] = instances

        let liveCount = instances.count
        peakCounts[typeName] = max(peakCounts[typeName] ?? 0, liveCount)

        lock.unlock()

        writeLog(
            event: "INIT",
            typeName: typeName,
            instanceIdentifier: instanceIdentifier,
            liveCount: liveCount
        )
    }

    func recordDeinitialization(
        typeName: String,
        instanceIdentifier: String
    ) {
        lock.lock()

        var instances = liveInstances[typeName] ?? []
        let wasTracked = instances.remove(instanceIdentifier) != nil
        liveInstances[typeName] = instances

        let liveCount = instances.count

        lock.unlock()

        // Sebelumnya jumlah negatif dijepit ke nol dengan `max(0, ...)`.
        // Itu menyembunyikan akuntansi yang rusak — deinit tanpa init
        // pasangannya berarti ada yang salah, dan lebih baik berisik.
        assert(
            wasTracked,
            "DEINIT \(typeName) [\(instanceIdentifier)] tanpa INIT pasangannya."
        )

        writeLog(
            event: "DEINIT",
            typeName: typeName,
            instanceIdentifier: instanceIdentifier,
            liveCount: liveCount
        )
    }

    // MARK: - Checkpoint

    /// Tipe yang masih punya instance hidup, beserta jumlahnya.
    ///
    /// Panggil saat aplikasi kembali ke root. Apa pun yang muncul di sini
    /// adalah objek yang belum dilepas — daftar tersangka yang spesifik,
    /// bukan log yang harus digulir.
    func liveTypes() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }

        return liveInstances
            .filter { !$0.value.isEmpty }
            .mapValues { $0.count }
    }

    /// Identifier instance yang masih hidup untuk satu tipe. Nilainya adalah
    /// alamat objek dalam hex, sehingga bisa dicari langsung di Memory Graph
    /// Debugger saat Anda perlu tahu siapa yang masih menahannya.
    func liveInstanceIdentifiers(of typeName: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        return Array(liveInstances[typeName] ?? []).sorted()
    }

    /// Jumlah tertinggi yang pernah hidup bersamaan untuk satu tipe.
    func peakCount(of typeName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        return peakCounts[typeName] ?? 0
    }

    /// Ringkasan siap cetak untuk debug menu.
    func snapshotDescription() -> String {
        let live = liveTypes()

        guard !live.isEmpty else {
            return "[LIFECYCLE] Tidak ada objek terlacak yang masih hidup."
        }

        let rows = live
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { typeName, count in
                "  \(count)x \(typeName) (puncak \(peakCount(of: typeName)))"
            }
            .joined(separator: "\n")

        return "[LIFECYCLE] Masih hidup:\n\(rows)"
    }

    /// Untuk dipakai di test: kosongkan seluruh catatan.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        liveInstances.removeAll()
        peakCounts.removeAll()
    }

    // MARK: - Log

    private func writeLog(
        event: String,
        typeName: String,
        instanceIdentifier: String,
        liveCount: Int
    ) {
        guard loggingPolicy.allows(typeName) else { return }

        let message = """
        [LIFECYCLE] \(event) \(typeName) \
        [\(instanceIdentifier)] live=\(liveCount)
        """

        // Level `.info`, bukan `.debug`. Pesan `.debug` tersaring di
        // Console.app kecuali debug logging diaktifkan untuk subsystem-nya,
        // dan itu membuat orang menyimpulkan probe-nya tidak jalan.
        os_log(
            "%{public}@",
            log: log,
            type: .info,
            message as NSString
        )
    }
}

#endif
