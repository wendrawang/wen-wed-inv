import SwiftUI

/// Menyimpan hasil build destination supaya `destinationBuilder` hanya
/// dijalankan sekali, yaitu saat layar benar-benar di-push.
private final class LazyNavigationDestinationStorage<
    Destination: View
> {
    private let destinationBuilder: () -> Destination

    lazy var destination: Destination = destinationBuilder()

    init(destinationBuilder: @escaping () -> Destination) {
        self.destinationBuilder = destinationBuilder
    }
}

private struct LazyNavigationDestination<
    Destination: View
>: View {
    @State private var storage: LazyNavigationDestinationStorage<Destination>

    init(
        @ViewBuilder destinationBuilder: @escaping () -> Destination
    ) {
        _storage = State(
            initialValue: LazyNavigationDestinationStorage(
                destinationBuilder: destinationBuilder
            )
        )
    }

    var body: some View {
        storage.destination
    }
}

/// `NavigationLink` yang menunda pembangunan destination sampai layar
/// benar-benar dibuka.
///
/// `NavigationLink(destination:)` biasa meng-construct destination-nya saat
/// body induk dievaluasi. Pada arsitektur coordinator, itu berarti membuka
/// satu layar ikut membangun seluruh pohon tujuannya secara berantai. Dengan
/// versi ini, cascade berhenti di satu tingkat: membuka layar A membangun
/// *link* milik B, tetapi bukan isi B.
///
/// Konsekuensi yang perlu diketahui: hasil build disimpan selama `@State`
/// destination masih hidup, dan `NavigationView` di iOS 13–14 tidak selalu
/// merobohkannya tepat saat pop. Objeknya tetap dilepas — saat slot dipakai
/// ulang atau saat ancestor-nya mati — jadi ini pelepasan tertunda, bukan
/// kebocoran. Lihat docs/LIFECYCLE_RULES.md untuk cara mengukurnya.
struct LazyNavigationLink<
    Tag: Hashable,
    Destination: View
>: View {
    @Binding private var selection: Tag?

    private let tag: Tag
    private let destinationBuilder: () -> Destination

    init(
        tag: Tag,
        selection: Binding<Tag?>,
        @ViewBuilder destinationBuilder: @escaping () -> Destination
    ) {
        self.tag = tag
        self._selection = selection
        self.destinationBuilder = destinationBuilder
    }

    var body: some View {
        NavigationLink(
            destination: LazyNavigationDestination(
                destinationBuilder: destinationBuilder
            ),
            tag: tag,
            selection: $selection
        ) {
            EmptyView()
        }
        .invisible()
    }
}
