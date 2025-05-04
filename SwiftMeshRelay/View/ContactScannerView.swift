//
//  QRScanView.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import VisionKit
import SwiftData

struct ContactScannerView: UIViewControllerRepresentable {
    @Environment(\.modelContext) private var context
    @Binding var isPresenting: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ContactScannerViewController {
        let vc = ContactScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ContactScannerViewController, context: Context) {}

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        let parent: ContactScannerView
        init(_ parent: ContactScannerView) {
            self.parent = parent
        }

        func didFind(card: ContactCard) {
            Task { @MainActor in
                ContactShareStore.store(card, in: parent.context)
                parent.isPresenting = false
            }
        }
    }
}
