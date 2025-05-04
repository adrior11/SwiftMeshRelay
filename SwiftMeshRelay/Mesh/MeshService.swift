//
//  MeshService.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  MIT License
//
//  Copyright (c) 2025 Adrian Schneider
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import CryptoKit
import Foundation
import MultipeerConnectivity
import SwiftData
import os

@MainActor
final class MeshService: NSObject, ObservableObject {
    private let log = Logger(subsystem: "mesh", category: "core")

    // MARK: - Public Singleton

    static let shared = MeshService()

    // MARK: - Published State

    @Published fileprivate(set) var reachablePeers: [MCPeerID] = []
    @Published fileprivate(set) var lastInbound: (from: UUID, text: String)?

    // MARK: - Public API

    func configure(container: ModelContainer) {
        self.context = container.mainContext
        advertiser.delegate = self
        browser.delegate = self
        log.info("Configured mesh service")
    }

    func start() {
        guard state == .stopped else { return }
        log.info("Starting mesh service...")
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        runBeaconTimer()
        state = .running
        log.info("Mesh service started")
    }

    func stop() {
        guard state == .running else { return }
        log.info("Stopping mesh service...")
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        beaconTimer?.cancel()
        beaconTimer = nil
        sessions.values.forEach { $0.disconnect() }
        sessions.removeAll()
        state = .stopped
        log.info("Mesh service stopped")
    }

    func sendMessage(_ text: String, to dest: UUID) throws {
        log.info("Sending message to \(dest.uuidString.prefix(8)): \(text)")
        let plaintext = Data(text.utf8)
        let symm = try deriveSymmetricKey(to: dest)
        let sealed = try ChaChaPoly.seal(plaintext, using: symm)

        queueFrame(dest: dest, ttl: MeshConfig.defaultTTL, cipher: sealed.combined)
        try? flush()
    }

    // MARK: - Private Types & State

    private enum RunState { case stopped, running }
    private var state: RunState = .stopped

    // MARK: Identity (Curve25519)

    private lazy var privateKey: Curve25519.KeyAgreement.PrivateKey = {
        if let data = KeychainHelper.load(tag: "eqmesh.identity") {
            return try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        KeychainHelper.save(key.rawRepresentation, tag: "eqmesh.identity")
        return key
    }()

    internal var myID: UUID { UUID(uuid: privateKey.publicKey.rawRepresentation.sha256Prefix16()) }

    // MARK: Multipeer Connectivity

    internal let myPeer = MCPeerID(displayName: UIDevice.current.name)
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: myPeer, discoveryInfo: nil, serviceType: MeshConfig.serviceType)
    private lazy var browser = MCNearbyServiceBrowser(
        peer: myPeer, serviceType: MeshConfig.serviceType)
    internal var sessions: [MCPeerID: MCSession] = [:]

    // MARK: Routing

    private var seqNo: UInt32 = 0
    private var bestNextHop: [UUID: MCPeerID] = [:]
    private var lastSeq: [UUID: UInt32] = [:]

    // MARK: Persistence

    private var context: ModelContext!

    // MARK: - Beaconing

    private var beaconTimer: DispatchSourceTimer?

    private func runBeaconTimer() {
        beaconTimer?.cancel()
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now(), repeating: MeshConfig.beaconInterval)
        timer.setEventHandler { [weak self] in self?.broadcastBeacon() }
        timer.resume()
        beaconTimer = timer
    }

    private func broadcastBeacon() {
        guard !sessions.isEmpty else { return }
        seqNo &+= 1

        let beacon = Beacon(origin: myID, seqNo: seqNo, ttl: MeshConfig.defaultTTL, hop: 0)

        guard let header = try? JSONEncoder().encode(beacon) else { return }
        let packet = buildPacket(type: .frame, header: header)

        sessions.values.forEach {
            try? $0.send(packet, toPeers: $0.connectedPeers, with: .unreliable)
        }
    }

    // MARK: - Frame queue

    private func queueFrame(dest: UUID, ttl: UInt8, cipher: Data) {
        let frameID = dest.uuidString + "|" + String(seqNo)
        let entity = FrameEntity(
            frameID: frameID, sourceID: myID, destID: dest, ttl: ttl, cipherBlob: cipher)
        context.insert(entity)
        try? context.save()
    }

    private func flush() throws {
        let fetch = FetchDescriptor<FrameEntity>(predicate: #Predicate { $0.ttlRemaining > 0 })
        guard let frames = try? context.fetch(fetch) else { return }

        for frame in frames {
            sendFrame(frame)
            frame.ttlRemaining &-= 1
            if frame.ttlRemaining == 0 {
                context.delete(frame)
            }
        }
        try? context.save()
    }

    private func sendFrame(_ frame: FrameEntity) {
        let header = FrameHeader(
            origin: myID,
            dest: frame.destID,
            ttl: frame.ttlRemaining,
            seq: frame.createdAt.timeIntervalSince1970.bitPattern)
        guard let headerData = try? JSONEncoder().encode(header) else { return }
        let packet = buildPacket(
            type: .frame,
            header: headerData,
            body: frame.cipherBlob)

        let targetSessions: [MCSession]
        if let hop = bestNextHop[frame.destID],
            let sess = sessions[hop]
        {
            targetSessions = [sess]
        } else {
            log.info("No route for \(frame.destID). Flooding to all peers.")
            targetSessions = Array(sessions.values)
        }

        for sess in targetSessions {
            do {
                try sess.send(packet, toPeers: sess.connectedPeers, with: .reliable)
            } catch {
                log.error("send error: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Contact Card

    var myContactCard: ContactCard {
        .init(
            uuid: myID, nickname: UIDevice.current.name,
            pubKey: privateKey.publicKey.rawRepresentation)
    }

    // MARK: - Crypto helper

    private func deriveSymmetricKey(to dest: UUID) throws -> SymmetricKey {
        guard let keyData = KeyStore.pubKey(for: dest, in: context) else {
            log.error("Public key for \(dest) not found")
            throw MeshError.pubKeyMissing
        }
        let peerPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyData)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peerPub)

        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }

    // MARK: - Incoming Packet Handlers

    /*
    private func handleBeacon(_ hdr: Data, via peer: MCPeerID) {
        guard var b = try? JSONDecoder().decode(Beacon.self, from: hdr) else { return }
    
        if let seen = lastSeq[b.origin], seen >= b.seqNo { return }
        lastSeq[b.origin] = b.seqNo
        bestNextHop[b.origin] = peer
    
        guard b.ttl > 1 else { return }
        b.ttl &-= 1; b.hop &+= 1
        guard let rebroadcast = try? JSONEncoder().encode(b) else { return }
    
        let pkt = buildPacket(type: .beacon, header: rebroadcast)
        for session in sessions.values where session != sessions[peer] {
            try? session.send(pkt, toPeers: session.connectedPeers, with: .unreliable)
        }
    }
    */

    private func handleFrame(hdr: Data, cipher: Data, via peer: MCPeerID) {
        guard let h = try? JSONDecoder().decode(FrameHeader.self, from: hdr) else { return }

        if h.dest == myID {
            receiveLocalFrame(h, cipher: cipher, via: peer)
        } else {
            forwardFrame(h, cipher: cipher)
        }
    }

    private func receiveLocalFrame(_ header: FrameHeader, cipher: Data, via peer: MCPeerID) {
        guard let symm = try? deriveSymmetricKey(to: header.origin),
            let box = try? ChaChaPoly.SealedBox(combined: cipher),
            let clear = try? ChaChaPoly.open(box, using: symm),
            let text = String(data: clear, encoding: .utf8)
        else { return }

        lastInbound = (from: header.origin, text)
        log.info("📩 From \(peer.displayName): \(text)")
        sendAck(for: header, via: peer)
    }

    private func forwardFrame(_ header: FrameHeader, cipher: Data) {
        guard header.ttl > 1 else { return }
        var h = header
        h.ttl &-= 1

        let packet = buildPacket(
            type: .frame,
            header: try! JSONEncoder().encode(h),
            body: cipher
        )

        if let hop = bestNextHop[h.dest],
            let sess = sessions[hop]
        {
            try? sess.send(packet, toPeers: [hop], with: .reliable)
        } else {
            sessions.values.forEach {
                try? $0.send(packet, toPeers: $0.connectedPeers, with: .reliable)
            }
        }
    }

    private func sendAck(for header: FrameHeader, via peer: MCPeerID) {
        let ackID = withUnsafeBytes(of: header.seq.bigEndian, Array.init)  // 8‑byte ID
        let packet = buildPacket(type: .ack, header: Data(ackID))
        sessions[peer].map { try? $0.send(packet, toPeers: [$0.myPeerID], with: .reliable) }
    }

    private func handleAck(_ hdr: Data, via _: MCPeerID) {
        guard hdr.count == 8 else { return }
        // TODO: ack cleanup
    }
}

// MARK: - Multipeer Delegate Extension

@MainActor
extension MeshService: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate,
    MCSessionDelegate
{

    // MARK: - Multipeer Delegate Extension

    func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard sessions.count < MeshConfig.maxNeighbours else { return }
        browser.invitePeer(
            peerID, to: makeSession(for: peerID),
            withContext: privateKey.publicKey.rawRepresentation, timeout: 5)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        sessions[peerID]?.disconnect()
        sessions[peerID] = nil
        reachablePeers.removeAll { $0 == peerID }
    }

    // MARK: Advertiser Delegate

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, makeSession(for: peerID))
    }

    // MARK: Session Factory

    private func makeSession(for peer: MCPeerID) -> MCSession {
        if let existing = sessions[peer] { return existing }
        let session = MCSession(
            peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        sessions[peer] = session
        reachablePeers += [peer]
        return session
    }

    // MARK: Session Delegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            if !reachablePeers.contains(peerID) {
                reachablePeers.append(peerID)
            }
        case .notConnected:
            reachablePeers.removeAll { $0 == peerID }
            sessions[peerID] = nil
        default:
            break
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count > 3,
            let type = PacketType(rawValue: data[0])
        else { return }

        let headerLength = Int(data[1]) << 8 | Int(data[2])
        guard data.count >= 3 + headerLength else { return }

        let header = data[3..<3 + headerLength]
        let body = data.dropFirst(3 + headerLength)

        switch type {
        //case .beacon: handleBeacon(header, via: peerID)
        case .frame: handleFrame(hdr: header, cipher: body, via: peerID)
        case .ack: handleAck(header, via: peerID)
        }
    }

    // Unused delegate methods
    func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}
    func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}
    func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}
