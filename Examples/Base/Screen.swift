import SwiftUI
import QuickLook

/// Base `Screen` dengan satu perubahan: nilai default `@ObservedObject`
/// dihapus supaya tidak ada `ScreenContentViewModel` yang dibuat lalu dibuang.
///
/// Sisanya identik dengan versi sebelumnya. Perubahannya ada di deklarasi
/// property dan `init` — lihat komentar di sana.
struct Screen<Content: ScreenContent>: View {
    @EnvironmentObject var appState: AppState

    /// Tidak punya sumber dari luar, jadi memang harus dibuat di sini.
    ///
    /// Karena `@ObservedObject` tidak memiliki objeknya dan iOS 13 tidak punya
    /// `@StateObject`, state-nya (`isRunningInBackground`) ikut hilang setiap
    /// struct `Screen` di-init ulang. Dengan `LazyNavigationLink`, `Screen`
    /// hanya dibangun sekali per push sehingga tidak muncul masalah. Kalau
    /// ingin benar-benar aman, pindahkan `isRunningInBackground` ke
    /// `ScreenContentViewModel` yang kepemilikannya jelas ada di coordinator,
    /// lalu hapus `ScreenViewModel` dari sini.
    @ObservedObject private var viewModel = ScreenViewModel()

    /// **Tanpa nilai default.**
    ///
    /// Sebelumnya `= ScreenContentViewModel()`. Nilai default stored property
    /// dievaluasi pada **setiap** init struct, lalu langsung ditimpa di `init`
    /// oleh `content.viewModel` — jadi setiap konstruksi `Screen` membuat satu
    /// `ScreenContentViewModel` lengkap, dengan 20-an `@Published`, dua
    /// pendaftaran `NotificationCenter`, dan beberapa closure, hanya untuk
    /// dibuang sedetik kemudian.
    @ObservedObject private var contentViewModel: ScreenContentViewModel

    private let content: Content

    var body: some View {
        if #available(iOS 15.0, *) {
            render()
                .dynamicTypeSize(.large)
        } else {
            render()
                .environment(\.sizeCategory, .large)
        }
    }

    /// Membangun `content` sekali, lalu memasang `contentViewModel` langsung
    /// dari objeknya lewat `_contentViewModel` — tanpa objek perantara yang
    /// dibuang.
    ///
    /// Bentuk `lazy` tidak bisa dipakai di sini seperti pada `useCase` di
    /// ViewModel, karena property wrapper tidak boleh `lazy`.
    init(_ content: () -> (Content)) {
        let builtContent = content()

        self.content = builtContent
        self._contentViewModel = ObservedObject(
            wrappedValue: builtContent.viewModel
        )
    }

    private func onAppear() {
        contentViewModel.initState()
        contentViewModel.loadData()
    }

    private func renderErrorView() -> some View {
        ZStack {
            renderBottomSheet()
            renderMessageScreen()
            renderNetworkUnavailable()
        }
    }

    private func renderScreenLoading() -> some View {
        Group {
            Rectangle()
                .fill(Colors.Black.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)

            ActivityIndicatorView()
        }
        .setHidden(!contentViewModel.isPresentingScreenLoading)
    }

    private func renderContent() -> some View {
        NavigationBarView(
            viewModel: contentViewModel.navigationBarViewModel,
            snackbar: {
                self.renderSnackBar()
            },
            content: {
                content.onAppear(perform: onAppear)
            }
        )
    }

    private func renderPdfQuickLookView() -> some View {
        PdfQuickLookView(
            viewModel: contentViewModel.pdfQuickLookViewModel
        )
    }

    private func renderSheetView() -> some View {
        ZStack {
            renderActivityView()
            renderMessageComposer()
            renderImagePicker()
            renderContactPicker()
            renderMailView()
            renderSafariView()
        }
    }

    private func renderPreviewImage() -> some View {
        ImagePreviewView(
            viewModel: contentViewModel.imagePreviewViewModel
        )
    }

    private func render() -> some View {
        ZStack {
            renderContent()
            renderPdfQuickLookView()
            renderErrorView()
                .zIndex(ZIndexValues.mostTop)
            renderPreviewImage()
                .zIndex(ZIndexValues.mostTop)
            renderScreenLoading()
                .zIndex(ZIndexValues.mostTop)
        }
        .blur(
            radius: viewModel.isRunningInBackground
                ? BlurLevels.low
                : DefaultValues.emptyCGFloat
        )
        .sheet(
            isPresented: $contentViewModel.isShowingSheet,
            content: {
                renderSheetView()
            }
        )
        .background(
            contentViewModel.backgroundColor.edgesIgnoringSafeArea(.all)
        )
        .navigationBarTitle(
            Text(DefaultValues.emptyString),
            displayMode: .inline
        )
        .navigationBarHidden(true)
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willResignActiveNotification
            ),
            perform: { _ in self.willEnterBackground() }
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            ),
            perform: { _ in self.willEnterForeground() }
        )
        .uiKitEvent(
            onViewDidAppear: contentViewModel.viewDidAppear,
            onViewDidDisappear: contentViewModel.viewDidDisappear
        )
    }
}

extension Screen {
    private func renderBottomSheet() -> some View {
        BottomSheetView(
            viewModel: contentViewModel.bottomSheetViewModel
        )
    }

    private func renderMessageScreen() -> some View {
        MessageScreenNavigation(
            viewModel: contentViewModel.messageScreenNavigationViewModel
        )
    }

    private func renderNetworkUnavailable() -> some View {
        MessageScreenNavigation(
            viewModel: contentViewModel.networkUnavailableNavigationViewModel
        )
    }

    private func renderSnackBar() -> some View {
        SnackBarView(
            viewModel: contentViewModel.snackBarViewModel
        )
    }
}

extension Screen {
    private func willEnterBackground() {
        viewModel.willEnterBackground()
        contentViewModel.willEnterBackground(appState: appState)
    }

    private func willEnterForeground() {
        viewModel.willEnterForeground(appState: appState)
        contentViewModel.willEnterForeground(appState: appState)
    }
}

extension Screen {
    private func renderActivityView() -> some View {
        PrimitiveActivityView(
            viewModel: contentViewModel.shareSheetViewModel
        )
        .setHidden(contentViewModel.sheetState != .shareActivity)
    }

    private func renderMessageComposer() -> some View {
        PrimitiveMessageComposer(
            viewModel: contentViewModel.messageComposerViewModel
        )
        .setHidden(contentViewModel.sheetState != .messageComposer)
    }

    private func renderImagePicker() -> some View {
        PrimitiveImagePicker(
            viewModel: contentViewModel.primitiveImagePickerViewModel
        )
        .setHidden(contentViewModel.sheetState != .imagePicker)
    }

    private func renderContactPicker() -> some View {
        PrimitiveContactPicker(
            viewModel: contentViewModel.primitiveContactPickerViewModel
        )
        .setHidden(contentViewModel.sheetState != .contactPicker)
    }

    private func renderMailView() -> some View {
        MailView(
            viewModel: contentViewModel.sheetMailViewModel
        )
        .setHidden(contentViewModel.sheetState != .mail)
    }

    private func renderSafariView() -> some View {
        ZStack {
            if let safariSheetUrl = contentViewModel.safariSheetUrl {
                SafariView(
                    url: safariSheetUrl,
                    dismiss: contentViewModel.dismissSheet
                )
                .setHidden(contentViewModel.sheetState != .safari)
            }
        }
    }
}
