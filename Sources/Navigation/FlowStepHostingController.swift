import SwiftUI
import UIKit

/// Controller yang tahu ia mewakili langkah apa di dalam flow.
///
/// Penandanya ada supaya "kembali ke langkah B" bisa dinyatakan sebagai nama,
/// bukan sebagai hitungan mundur. Hitungan mundur rapuh: begitu sebuah langkah
/// bersyarat ikut masuk atau tidak masuk ke tumpukan, angkanya salah, dan
/// salahnya baru terlihat di tangan pengguna.
protocol FlowStepHosting: AnyObject {
    var stepIdentifier: String? { get set }
}

/// Pembungkus layar SwiftUI di dalam tumpukan flow.
class FlowStepHostingController<
    Content: View
>: UIHostingController<Content>, FlowStepHosting {

    var stepIdentifier: String?
}

/// Menandai controller yang isinya sub-flow SwiftUI dengan `NavigationView`
/// sendiri di dalamnya.
///
/// Penandanya dibutuhkan karena dua gestur swipe-back tidak bisa hidup
/// bersamaan: milik `UINavigationController` di luar, dan milik `NavigationView`
/// di dalam. `FlowNavigationController` memilih mana yang aktif berdasarkan
/// kedalaman pulau.
protocol FlowIslandHosting: AnyObject {}

final class FlowIslandHostingController<
    Content: View
>: FlowStepHostingController<Content>, FlowIslandHosting {}
