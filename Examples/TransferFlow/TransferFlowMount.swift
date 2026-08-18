import SwiftUI

extension View {

    /// Memasang flow transfer. Cukup **sekali**, di layar paling luar.
    ///
    /// Setelah terpasang, seluruh aplikasi bisa membuka flow ini tanpa
    /// menyentuh view mana pun:
    ///
    /// ```swift
    /// transferFlowEntry.start(
    ///     .landing(transferCart: TransferCart(), category: .idr)
    /// )
    /// ```
    ///
    /// Dipasang di layar terluar, bukan di Dashboard, supaya flow-nya bisa
    /// dibuka dari tab mana pun — termasuk dari layar yang sedang tampil di
    /// atas Dashboard.
    func mountTransferFlow(
        screenFactories: TransferScreenFactories
    ) -> some View {
        modifier(
            FlowEntryModifier(entryStore: transferFlowEntry) { navigator, route in
                TransferFlowCoordinator(
                    navigator: navigator,
                    screenFactories: screenFactories
                )
                .createStack(enteringAt: route)
            }
        )
    }
}

// =============================================================================
// MENYEBERANG ANTAR DUNIA
//
// Empat arah, dan semuanya sudah punya jalannya. Ditulis di sini supaya ada di
// dekat kodenya, bukan hanya di dokumen.
//
//
// 1. SwiftUI → awal flow transfer
//
//    transferFlowEntry.start(.landing(transferCart: cart, category: .idr))
//
//    Tidak perlu `@State`, tidak perlu `Binding`, tidak perlu berada dekat
//    dengan layar tujuan.
//
//
// 2. SwiftUI → tengah flow transfer
//
//    transferFlowEntry.start(.transactionAmount(useCase: useCase))
//
//    Sama persis, hanya rutenya yang berbeda. Coordinator menyusun landing di
//    bawah dan tujuannya di atas, jadi tombol back tetap masuk akal. Kalau
//    sebuah rute justru **tidak** boleh bisa mundur ke landing, ubah
//    `createMidFlowStack` untuk rute itu menjadi satu layar saja — itu
//    keputusan produk, dan tempatnya memang di coordinator.
//
//
// 3. Flow transfer → layar SwiftUI (daun)
//
//    navigator.push(
//        Screen { SomeScreen(viewModel: createSomeViewModel()) }
//    )
//
//    Layarnya tidak perlu diubah sama sekali. Yang tidak terpakai hanyalah
//    coordinator SwiftUI-nya, karena ia semata mesin navigasi.
//
//
// 4. Flow transfer → rangkaian SwiftUI yang belum bisa diurai
//
//    navigator.pushIsland(
//        SomeExistingCoordinator(...)
//    )
//
//    Seluruh rangkaian menjadi satu entri di tumpukan; keluar berarti keluar
//    seluruhnya. Pakai ini sebagai jembatan sementara, bukan tujuan akhir —
//    begitu Anda ingin mundur ke langkah tertentu di dalamnya, ia harus jadi
//    flow tersendiri.
//
//
// Yang tidak boleh: mempresentasikan flow dari dalam flow. Modal di atas modal
// membuat penutupannya jadi tebakan. Di dalam flow, semuanya push.
// =============================================================================
