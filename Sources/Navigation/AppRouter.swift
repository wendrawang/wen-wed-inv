import SwiftUI

/// Satu flow yang siap dibuka, beserta cara menyusun tumpukannya.
///
/// Sengaja hanya berisi closure, bukan enum berisi seluruh tujuan aplikasi.
/// Alasannya ada di `AppRouter` di bawah.
struct PendingFlow {

    let createStack: (FlowNavigator) -> [UIViewController]

    init(createStack: @escaping (FlowNavigator) -> [UIViewController]) {
        self.createStack = createStack
    }
}

/// Router global untuk **seluruh** aplikasi.
///
/// Dari mana pun, tanpa `Binding`, tanpa `@State`, tanpa harus dekat dengan
/// layar tujuan:
///
/// ```swift
/// AppRouter.shared.start(.transfer(.landing(transferCart: cart, category: .idr)))
/// ```
///
/// ## Kenapa daftar tujuannya **tidak** ikut global
///
/// Godaan berikutnya adalah menaruh seluruh tujuan aplikasi dalam satu enum
/// raksasa. Untuk aplikasi ratusan layar, itu berakhir buruk dengan cara yang
/// bisa diramalkan:
///
/// - Satu file berisi ratusan case — jauh melewati batas 250 baris, dan setiap
///   tim menyunting file yang sama.
/// - Enum itu harus melihat tipe payload **semua** layar, jadi ia bergantung
///   pada seluruh aplikasi. Mengubah satu model berarti mengompilasi ulang
///   router, dan router dipakai semua orang.
/// - Karena itu jadi berat, orang menurunkannya menjadi `String` plus
///   `[String: Any]` — dan itu persis `destinationCoordinatorName` yang baru
///   kita tinggalkan, hanya dengan nama baru.
/// - "Tombol back membawa ke mana" adalah keputusan per flow. Router global
///   tidak bisa menyatakan `[landing, amount]` tanpa tahu bentuk tiap flow.
///
/// Yang global di sini adalah **mekanismenya**, bukan daftarnya. Setiap flow
/// menyimpan rutenya sendiri — kecil, dimiliki timnya, dikompilasi terpisah —
/// lalu mendaftar lewat satu `static func` di extension `PendingFlow`. File ini
/// tidak pernah ikut tumbuh. Menambah flow baru tidak menyentuh satu baris pun
/// di sini.
///
/// ## Satu flow pada satu waktu
///
/// Hanya ada satu `pendingFlow`. Itu disengaja: ia menegakkan aturan "presentasi
/// untuk menyeberang dunia, push untuk bergerak di dalam flow", sehingga modal
/// di atas modal tidak bisa terjadi karena kelalaian.
final class AppRouter: ObservableObject {

    static let shared = AppRouter()

    @Published private(set) var pendingFlow: PendingFlow?

    var isPresenting: Bool {
        pendingFlow != nil
    }

    private init() {}

    /// Membuka sebuah flow.
    ///
    /// **Ini pintu masuk flow, bukan cara berpindah di dalamnya.** Sekali sebuah
    /// flow tampil, perpindahan berikutnya memakai `navigator.push` — memanggil
    /// ini lagi tidak akan menampilkan apa pun, karena hanya ada satu flow pada
    /// satu waktu.
    ///
    /// Dulu itu gagal diam-diam: `pendingFlow` berganti, `isPresenting` tetap
    /// `true`, dan `FlowPresenter` menganggap tidak ada yang perlu dikerjakan.
    /// Sekarang berisik di Debug.
    func start(_ flow: PendingFlow) {
        if isPresenting {
            assertionFailure(
                """
                A flow is already presented, so starting another one does \
                nothing. Only one flow can be presented at a time. To move \
                within the flow that is already open, push onto its \
                FlowNavigator instead. To replace it, call finish() on the \
                current flow first, then start the new one.
                """
            )
            return
        }

        pendingFlow = flow
    }

    /// Dipanggil saat flow benar-benar ditutup.
    ///
    /// `pendingFlow` menahan apa pun yang ditangkap closure-nya — termasuk
    /// UseCase, kalau rutenya membawa satu. Karena itu dikosongkan saat flow
    /// ditutup, bukan saat dibuka.
    func clear() {
        pendingFlow = nil
    }
}

// MARK: - Pemasangan

/// Memasang router ke pohon view. Dipasang **sekali**, di view paling luar,
/// di luar `NavigationView`.
struct AppRouterModifier: ViewModifier {

    @ObservedObject private var router = AppRouter.shared

    func body(content: Content) -> some View {
        content.background(
            FlowPresenter(isPresented: presentationBinding) { navigator in
                router.pendingFlow?.createStack(navigator) ?? []
            }
        )
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: {
                router.isPresenting
            },
            set: { isPresenting in
                if !isPresenting {
                    router.clear()
                }
            }
        )
    }
}

extension View {

    /// ```swift
    /// NavigationView {
    ///     DashboardCoordinator()
    /// }
    /// .mountFlowRouter()
    /// ```
    ///
    /// Tidak ada argumen, dan tidak bertambah saat flow baru ditambahkan.
    func mountFlowRouter() -> some View {
        modifier(AppRouterModifier())
    }
}
