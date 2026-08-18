import SwiftUI

/// Titik masuk global untuk sebuah flow.
///
/// Satu instance per flow, disimpan sebagai konstanta global. Layar mana pun,
/// di dunia mana pun, cukup memanggil `start(_:)` dengan rute tujuannya —
/// tanpa tahu apa pun tentang isi flow itu, tanpa `Binding` yang dioper
/// berlapis-lapis, dan tanpa perlu berada di dekat layar yang dituju.
///
/// Ini yang menjawab "dari tengah flow SwiftUI, masuk ke tengah flow transfer":
/// rute yang disimpan di sini bukan hanya "buka flow-nya", tetapi "buka flow-nya
/// **di langkah ini**".
///
/// ## Umur objek
///
/// `pendingRoute` menahan apa pun yang dibawa rutenya — termasuk UseCase, kalau
/// rutenya membawa satu. Karena itu ia dikosongkan saat flow ditutup, bukan saat
/// flow dibuka: selama flow tampil, rutenya memang masih dibutuhkan; setelah
/// ditutup, tidak ada yang boleh tersisa di sini.
final class FlowEntryStore<Route>: ObservableObject {

    @Published private(set) var pendingRoute: Route?

    var isPresenting: Bool {
        pendingRoute != nil
    }

    /// Membuka flow pada rute tertentu. Aman dipanggil dari mana saja.
    func start(_ route: Route) {
        pendingRoute = route
    }

    /// Dipanggil saat flow benar-benar ditutup.
    func clear() {
        pendingRoute = nil
    }
}

/// Memasang sebuah flow ke pohon view SwiftUI.
///
/// Dipasang **sekali**, di layar paling luar. Setelah itu setiap layar cukup
/// memanggil `start(_:)` pada store-nya.
struct FlowEntryModifier<Route>: ViewModifier {

    @ObservedObject var entryStore: FlowEntryStore<Route>

    let createStack: (FlowNavigator, Route) -> [UIViewController]

    func body(content: Content) -> some View {
        content.background(
            FlowPresenter(isPresented: presentationBinding) { navigator in
                guard let pendingRoute = entryStore.pendingRoute else {
                    return []
                }

                return createStack(navigator, pendingRoute)
            }
        )
    }

    /// Menutup flow berarti mengosongkan rutenya, supaya keduanya tidak pernah
    /// punya dua versi kebenaran.
    private var presentationBinding: Binding<Bool> {
        Binding(
            get: {
                entryStore.isPresenting
            },
            set: { isPresenting in
                if !isPresenting {
                    entryStore.clear()
                }
            }
        )
    }
}
