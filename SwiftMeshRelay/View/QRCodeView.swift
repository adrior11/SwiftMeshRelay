//
//  ContactQRView.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import SwiftData

struct QRCodeView: View {
    let contactCard: ContactCard
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    
    private func generateQRCode() -> UIImage? {
        // Encode ContactCard as Base64-encoded JSON
        guard let jsonData = try? JSONEncoder().encode(contactCard) else { return nil }
        let b64 = jsonData.base64EncodedString()
        let data = Data(b64.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        if let cgImg = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cgImg)
        }
        return nil
    }

    var body: some View {
        VStack {
            if let uiImage = generateQRCode() {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .padding()
            } else {
                Text("Unable to generate QR Code")
                    .foregroundColor(.secondary)
            }
            Text("Scan this code to add \(contactCard.nickname)")
                .font(.caption)
                .padding(.top)
        }
        .navigationTitle("My QR Code")
    }
}
