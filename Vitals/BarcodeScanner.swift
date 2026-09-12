import SwiftUI
import VisionKit

/// Live barcode scanner for packaged foods (Open Food Facts lookup follows).
struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue {
                    fired = true
                    dataScanner.stopScanning()
                    onCode(s)
                    return
                }
            }
        }
    }
}

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void
    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScanner.isSupported {
                    BarcodeScanner { code in dismiss(); onCode(code) }.ignoresSafeArea()
                } else {
                    ContentUnavailableView("Barcode scanning needs a camera", systemImage: "barcode.viewfinder", description: Text("On a real iPhone this opens the camera. You can also photograph the barcode with the Scan button — it's detected in the photo too."))
                }
            }
            .navigationTitle("Scan a barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
