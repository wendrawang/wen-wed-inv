import SwiftUI

/// Pendaftaran flow transfer ke router global.
///
/// **Ini seluruh biaya menambahkan sebuah flow**: satu `static func` di file
/// milik flow itu sendiri. `AppRouter` tidak ikut berubah, dan tidak akan
/// pernah ikut tumbuh berapa pun flow yang ditambahkan.
///
/// Flow berikutnya bentuknya sama persis:
///
/// ```swift
/// extension PendingFlow {
///     static func payment(_ route: PaymentRoute) -> PendingFlow {
///         PendingFlow { navigator in
///             PaymentFlowCoordinator(navigator: navigator, screenFactories: .live)
///                 .createStack(enteringAt: route)
///         }
///     }
/// }
/// ```
extension PendingFlow {

    /// Membuka flow transfer pada rute tertentu.
    ///
    /// ```swift
    /// AppRouter.shared.start(
    ///     .transfer(.landing(transferCart: cart, category: .idr))
    /// )
    /// ```
    ///
    /// `screenFactories` punya nilai default supaya call site tetap satu baris,
    /// tetapi tetap bisa diganti di test tanpa menyentuh apa pun yang global.
    static func transfer(
        _ route: TransferRoute,
        screenFactories: TransferScreenFactories = .live
    ) -> PendingFlow {
        PendingFlow { navigator in
            TransferFlowCoordinator(
                navigator: navigator,
                screenFactories: screenFactories
            )
            .createStack(enteringAt: route)
        }
    }
}

// =============================================================================
// YANG HARUS ANDA SEDIAKAN
//
// `TransferScreenFactories.live` belum ada di repo ini, dan itu disengaja —
// tujuh layar tujuannya belum pernah saya lihat, jadi menuliskannya berarti
// menebak. Kompilernya akan menagih Anda, dan itu memang yang diinginkan:
//
//     extension TransferScreenFactories {
//         static let live = TransferScreenFactories(
//             createNewRecipient: { useCase, category in ... },
//             createTransactionAmount: { useCase in ... },
//             ...
//         )
//     }
//
// Sebelum sebuah tujuan punya factory-nya sendiri, jembatan sementaranya
// `navigator.pushIsland(CoordinatorLamaNya(...))` — lihat bagian di bawah.
// =============================================================================

// =============================================================================
// MENYEBERANG ANTAR DUNIA
//
// Empat arah, ditulis di sini supaya ada di dekat kodenya.
//
//
// 1. SwiftUI → awal flow transfer
//
//    AppRouter.shared.start(.transfer(.landing(transferCart: cart, category: .idr)))
//
//
// 2. SwiftUI → tengah flow transfer
//
//    AppRouter.shared.start(.transfer(.transactionAmount(useCase: useCase)))
//
//    Sama persis, hanya rutenya yang berbeda. Coordinator menyusun landing di
//    bawah dan tujuannya di atas, jadi tombol back tetap masuk akal. Kalau
//    sebuah rute justru tidak boleh bisa mundur ke landing, ubah
//    `createMidFlowStack` untuk rute itu — keputusan produk, dan tempatnya
//    memang di coordinator.
//
//
// 3. Flow transfer → layar SwiftUI (daun)
//
//    navigator.push(Screen { SomeScreen(viewModel: createSomeViewModel()) })
//
//    Layarnya tidak perlu diubah. Yang tidak terpakai hanya coordinator
//    SwiftUI-nya, karena ia semata mesin navigasi.
//
//
// 4. Flow transfer → rangkaian SwiftUI yang belum bisa diurai
//
//    navigator.pushIsland(SomeExistingCoordinator(...))
//
//    Seluruh rangkaian menjadi satu entri di tumpukan; keluar berarti keluar
//    seluruhnya. Jembatan sementara, bukan tujuan akhir.
//
//
// Yang tidak boleh: mempresentasikan flow dari dalam flow. `AppRouter` hanya
// menyimpan satu `pendingFlow`, jadi aturan itu ditegakkan sendiri — di dalam
// flow, semuanya push.
// =============================================================================
