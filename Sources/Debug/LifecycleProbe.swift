#if DEBUG

import Foundation

/// Melacak umur satu objek: mencatat saat objek dibuat dan saat dilepas.
///
/// Probe ini **opt-in per class**, bukan dipasang di base class. Alasannya
/// disengaja: pada codebase yang masih punya banyak anomali, memasang probe
/// di base class akan menghasilkan ribuan baris log yang tidak ada yang baca,
/// dan rule yang tidak dibaca bukan rule. Pasang hanya pada tipe yang sedang
/// Anda audit, lalu perluas seiring waktu.
///
/// ## Bentuk yang diutamakan
///
/// Kalau `init` class-nya bisa Anda ubah, pakai bentuk ini. Nama tipe
/// diturunkan dari objeknya sendiri, jadi mustahil salah saat baris ini
/// di-copy ke class lain:
///
///     final class LoginUsernameUseCase: UseCase {
///         #if DEBUG
///         private var lifecycleProbe: LifecycleProbe?
///         #endif
///
///         override init() {
///             super.init()
///             #if DEBUG
///             lifecycleProbe = LifecycleProbe(self)
///             #endif
///         }
///     }
///
/// ## Bentuk cadangan
///
/// Kalau menambah `init` merepotkan, sebutkan tipenya secara eksplisit.
/// Perhatikan label `type:` — label ini wajib, supaya metatype tidak pernah
/// tertukar masuk ke inisialiser objek di atas:
///
///     final class LoginUsernameUseCase: UseCase {
///         #if DEBUG
///         private let lifecycleProbe = LifecycleProbe(
///             type: LoginUsernameUseCase.self
///         )
///         #endif
///     }
///
/// Bentuk cadangan punya satu risiko yang perlu Anda sadari: kalau baris ini
/// di-copy ke class lain dan nama tipenya lupa diganti, log tetap tercetak
/// rapi tetapi isinya salah. Utamakan bentuk pertama kalau bisa.
///
/// Probe tidak pernah menyimpan referensi ke objek yang dilacaknya, jadi
/// keberadaannya tidak pernah memperpanjang umur objek tersebut.
final class LifecycleProbe {

    private let typeName: String
    private let instanceIdentifier: String

    /// Bentuk yang diutamakan: nama tipe diambil dari `type(of: owner)`.
    ///
    /// `owner` hanya dibaca di dalam inisialiser ini dan tidak disimpan.
    init(_ owner: AnyObject) {
        let resolvedName = String(describing: type(of: owner))

        // Metatype (`Foo.self`) juga memenuhi `AnyObject` untuk class, sehingga
        // `LifecycleProbe(Foo.self)` akan diam-diam masuk ke sini dan mencatat
        // nama "Foo.Type". Ditangkap keras supaya tidak jadi log yang salah.
        assert(
            !resolvedName.hasSuffix(".Type"),
            """
            LifecycleProbe(_:) received a metatype, not an object. \
            Use LifecycleProbe(type: \(resolvedName)) instead, \
            or pass the instance itself.
            """
        )

        self.typeName = resolvedName
        self.instanceIdentifier = LifecycleProbe.identifier(
            for: ObjectIdentifier(owner)
        )

        LifecycleTracker.shared.recordInitialization(
            typeName: typeName,
            instanceIdentifier: instanceIdentifier
        )
    }

    /// Bentuk cadangan untuk class yang inisialisernya tidak bisa disentuh.
    init(type: Any.Type) {
        self.typeName = String(describing: type)
        self.instanceIdentifier = String(
            UUID().uuidString.prefix(8)
        )

        LifecycleTracker.shared.recordInitialization(
            typeName: typeName,
            instanceIdentifier: instanceIdentifier
        )
    }

    deinit {
        LifecycleTracker.shared.recordDeinitialization(
            typeName: typeName,
            instanceIdentifier: instanceIdentifier
        )
    }

    /// Alamat objek dalam hex, supaya baris log bisa dicocokkan langsung
    /// dengan node di Memory Graph Debugger dan Instruments.
    private static func identifier(
        for objectIdentifier: ObjectIdentifier
    ) -> String {
        "0x" + String(
            UInt(bitPattern: objectIdentifier),
            radix: 16
        )
    }
}

#endif
