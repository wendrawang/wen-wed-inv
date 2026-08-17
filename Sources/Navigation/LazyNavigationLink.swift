import SwiftUI

/// Menyimpan hasil build destination supaya `destinationBuilder` hanya
/// dijalankan sekali **per push**, lalu melepasnya lagi saat pop.
private final class LazyNavigationDestinationStorage<
    Destination: View
> {
    private let destinationBuilder: () -> Destination

    // PERUBAHAN: dulu `lazy var destination: Destination = destinationBuilder()`.
    //
    // `lazy var` tidak bisa dikosongkan lagi setelah terisi, dan di situlah
    // masalahnya: cache-nya berubah menjadi **pemilik**. Struct layar yang
    // tersimpan di sini memegang ViewModel-nya lewat `@ObservedObject`, jadi
    // selama storage hidup, ViewModel dan UseCase-nya juga hidup. Storage-nya
    // sendiri dipegang `@State` di dalam tautan, dan tautan itu ada di body
    // layar induk sepanjang layar induk ada. Untuk flow yang berangkat dari root
    // — Dashboard → Transfer Landing — itu berarti selamanya: INIT tercatat
    // sekali, DEINIT tidak pernah.
    private var cachedDestination: Destination?

    var destination: Destination {
        if let cachedDestination = cachedDestination {
            return cachedDestination
        }

        let builtDestination = destinationBuilder()
        cachedDestination = builtDestination
        return builtDestination
    }

    init(destinationBuilder: @escaping () -> Destination) {
        self.destinationBuilder = destinationBuilder
    }

    // PERUBAHAN: method baru. Melepas referensi cache-nya saja — bukan
    // menghancurkan layarnya. Selama SwiftUI masih menampilkan layar tujuan, ia
    // tetap memegang struct-nya sendiri, jadi memanggil ini di tengah animasi
    // pop aman: yang terjadi hanya satu referensi berkurang, dan DEINIT
    // menyusul saat SwiftUI ikut melepas.
    func releaseDestination() {
        cachedDestination = nil
    }
}

private struct LazyNavigationDestination<
    Destination: View
>: View {
    // PERUBAHAN: dulu `@State private var storage`, dibangun di `init` sini.
    // Storage-nya pindah ke `LazyNavigationLink` supaya tautannya bisa
    // melepasnya saat selection-nya lepas — view ini tidak punya akses ke
    // selection.
    let storage: LazyNavigationDestinationStorage<Destination>

    var body: some View {
        storage.destination
    }
}

/// `NavigationLink` yang menunda pembangunan destination sampai layar
/// benar-benar dibuka, dan melepasnya kembali saat ditutup.
///
/// `NavigationLink(destination:)` biasa meng-construct destination-nya saat
/// body induk dievaluasi. Pada arsitektur coordinator, itu berarti membuka
/// satu layar ikut membangun seluruh pohon tujuannya secara berantai. Dengan
/// versi ini, cascade berhenti di satu tingkat: membuka layar A membangun
/// *link* milik B, tetapi bukan isi B.
///
/// Sifat kedua yang sama pentingnya: hasil build dilepas begitu selection-nya
/// tidak lagi menunjuk tautan ini. Tanpa itu, ViewModel dan UseCase layar
/// tujuan berumur sepanjang layar **induk**, bukan sepanjang layar tujuan —
/// dan untuk flow yang berangkat dari root, itu berarti tidak pernah dilepas.
struct LazyNavigationLink<
    Tag: Hashable,
    Destination: View
>: View {
    @Binding private var selection: Tag?

    // PERUBAHAN: storage pindah ke sini dari `LazyNavigationDestination`.
    // `@State` di sini justru yang kita inginkan: tautannya ada di body induk
    // sepanjang layar induk hidup, jadi storage-nya stabil dan kita yang
    // menentukan kapan isinya dibuang — bukan `NavigationView`.
    @State private var storage: LazyNavigationDestinationStorage<Destination>

    private let tag: Tag

    init(
        tag: Tag,
        selection: Binding<Tag?>,
        @ViewBuilder destinationBuilder: @escaping () -> Destination
    ) {
        self.tag = tag
        self._selection = selection
        _storage = State(
            initialValue: LazyNavigationDestinationStorage(
                destinationBuilder: destinationBuilder
            )
        )
    }

    var body: some View {
        NavigationLink(
            // PERUBAHAN: storage dioper, tidak lagi dibangun di dalam sini.
            destination: LazyNavigationDestination(storage: storage),
            tag: tag,
            // PERUBAHAN: `$selection` menjadi `releasingSelection`.
            selection: releasingSelection
        ) {
            EmptyView()
        }
        .invisible()
    }

    // PERUBAHAN: pembungkus baru untuk binding selection.
    //
    // `NavigationView` menulis `nil` ke selection saat layar tujuan di-pop —
    // lewat tombol back maupun swipe. Titik itu satu-satunya tempat yang tahu
    // "tautan ini sudah tidak terpilih" tanpa efek samping di dalam `body` dan
    // tanpa `onChange` (iOS 14+) atau `onDisappear` (tidak dapat diandalkan di
    // `NavigationView` iOS 13 — ia juga menyala saat layar tertutup sheet).
    private var releasingSelection: Binding<Tag?> {
        Binding(
            get: {
                self.selection
            },
            set: { newValue in
                if newValue != self.tag {
                    self.storage.releaseDestination()
                }

                self.selection = newValue
            }
        )
    }
}
