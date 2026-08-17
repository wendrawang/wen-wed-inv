import SwiftUI

/// Memberi seluruh UseCase kemampuan `useCase.binding(\.output.x)`.
///
/// **Sengaja berdiri di file terpisah, bukan digabung ke `UseCase.swift`
/// maupun `UseCaseProtocol.swift`.**
///
/// `Binding` adalah tipe SwiftUI. Menaruh konformansi ini di file yang sama
/// dengan `UseCase` atau `UseCaseProtocol` memaksa kedua file itu meng-import
/// SwiftUI — padahal keduanya sekarang murni Foundation, dan menurut matriks
/// akses lapisan UseCase memang tidak seharusnya tahu apa pun soal view.
///
/// Konformansi retroaktif di file sendiri menjaga pemisahan itu: lapisan
/// UseCase tetap bebas UI, dan kebutuhan UI-nya ditambahkan dari sisi UI.
///
/// Menaruhnya di `UseCase` (class) atau di `UseCaseProtocol` sama-sama bekerja
/// dan cakupannya identik, karena setiap UseCase mewarisi keduanya. Yang dipilih
/// di sini adalah class-nya, karena `UseCaseProtocol` belum punya batasan
/// `AnyObject` — menambahkannya lewat `PropertyBindable` berarti menutup
/// kemungkinan protokol itu diadopsi tipe nilai, dan itu keputusan yang lebih
/// besar daripada sekadar menambah satu helper.
extension UseCase: PropertyBindable {}
