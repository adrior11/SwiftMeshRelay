//
//  MeshDebugView.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import SwiftUI
import SwiftData
import MultipeerConnectivity
import GroupActivities
import CryptoKit
import CoreTransferable

struct MeshDebugView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var contacts: [MeshContact]
    @ObservedObject private var mesh = MeshService.shared

    // Message composer
    @State private var draft: String = ""
    @State private var target: MeshContact?

    // Sheet state
    @State private var showingAdd = false
    @State private var showingMyQR = false
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            List {
                identitySection
                neighbourSection
                contactSection
                sendSection
                inboundSection
            }
            .navigationTitle("Mesh Debug")
            .font(.system(.caption, design: .monospaced))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingMyQR = true } label: {
                        Image(systemName: "qrcode")
                    }
                    Button { showingScanner = true } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showingMyQR) {
                QRCodeView(contactCard: MeshService.shared.myContactCard)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingScanner) {
                ContactScannerView(isPresenting: $showingScanner)
                    .presentationDetents([.medium])
            }
        }
    }
    
    // MARK: Sections
    private var identitySection: some View {
        Section("Identity") {
            Text("My ID » \(mesh.myID.uuidString.prefix(8))")
        }
    }

    private var neighbourSection: some View {
        Section("Neighbors") {
            Text("Reachable Peers: \(mesh.reachablePeers.count)")
        }
    }

    private var contactSection: some View {
        Section("Contacts") {
            ForEach(contacts) { c in
                HStack {
                    VStack(alignment: .leading) {
                        Text(c.nickname)
                        Text(c.uuid.uuidString.prefix(8))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if target?.uuid == c.uuid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { target = c }
            }
            .onDelete { index in
                index.map { contacts[$0] }.forEach(ctx.delete)
            }
        }
    }

    private var sendSection: some View {
        Section("Send") {
            if let t = target {
                Text("To: \(t.nickname)")
                    .font(.caption)
            } else {
                Text("Tap a contact to select")
                    .font(.caption)
            }
            TextField("Message", text: $draft)
            Button("Send") {
                guard let dest = target?.uuid, !draft.isEmpty else { return }
                try? mesh.sendMessage(draft, to: dest)
                draft = ""
            }
            .disabled(target == nil || draft.isEmpty)
        }
    }

    private var inboundSection: some View {
        Group {
            if let inbound = mesh.lastInbound {
                Section("Latest inbound") {
                    Text("from \(inbound.from.uuidString.prefix(8))")
                        .font(.caption)
                    Text(inbound.text)
                }
            }
        }
    }
}

#Preview {
    MeshDebugView()
}
