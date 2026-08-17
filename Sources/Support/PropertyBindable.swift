import SwiftUI

/// Memberi objek referensi kemampuan membuat `Binding` ke property-nya sendiri.
///
/// ## Kenapa ini ada
///
/// Selama coordinator menyimpan UseCase sebagai `@State`, binding ke output-nya
/// bisa ditulis dengan sintaks projected value:
///
///     recipientAccount: $useCase.output.recipientAccount
///
/// Bentuk itu hanya tersedia karena `@State` menyediakan `$`. Pada coordinator
/// yang sudah dimigrasi, UseCase dibangun di dalam `createDestination()` sebagai
/// objek biasa — tidak ada `$` untuk dipakai. Protokol ini menggantikannya:
///
///     recipientAccount: useCase.binding(\.output.recipientAccount)
///
/// ## Pemakaian
///
/// Daftarkan sekali di base class, lalu seluruh turunannya ikut:
///
///     extension UseCase: PropertyBindable {}
///
/// ## Kepemilikan
///
/// `Binding` yang dihasilkan menahan objeknya **secara kuat**, dan itu memang
/// yang diinginkan — sebuah binding tidak berarti apa-apa tanpa objek yang
/// ditunjuknya. Yang menahannya adalah pohon view, dan objeknya tidak menahan
/// pohon view balik, jadi tidak ada lingkaran yang terbentuk.
///
/// Perlu diperhatikan konsekuensinya: selama coordinator anak masih ada di
/// pohon, ia ikut memperpanjang umur UseCase milik induknya. Itu perilaku yang
/// sama dengan `@State` sebelumnya, hanya sekarang terlihat jelas.
protocol PropertyBindable: AnyObject {}

extension PropertyBindable {

    /// `Binding` dua arah ke sebuah property objek ini.
    ///
    ///     useCase.binding(\.output.recipientAccount)
    ///
    /// `ReferenceWritableKeyPath` menjamin di waktu kompilasi bahwa jalurnya
    /// berakar pada tipe referensi dan seluruh ruasnya bisa ditulis — jadi
    /// keypath yang salah tidak akan lolos.
    func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<Self, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
