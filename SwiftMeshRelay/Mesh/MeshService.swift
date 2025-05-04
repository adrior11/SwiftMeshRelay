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

// TODO: Refactor
@MainActor
final class MeshService: NSObject, ObservableObject {
    static let shared = MeshService()
    @Published fileprivate(set) var reachablePeers: [MCPeerID] = []
    @Published fileprivate(set) var lastInbound: (from: UUID, text: String)?

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

    /// High‑level API for UI calls
    func sendMessage(_ text: String, to dest: UUID) throws {
        log.info("Sending message to \(dest.uuidString.prefix(8)): \(text)")
        let plaintext = Data(text.utf8)
        log.info("Trying to derive symmetric key...")
        let symm = try deriveSymmetricKey(to: dest)
        log.info("Sealing message...")
        let sealed = try ChaChaPoly.seal(plaintext, using: symm)
        log.info("Queued message to \(dest.uuidString.prefix(8)): \(sealed.combined.count) bytes")
        queueFrame(dest: dest, ttl: MeshConfig.defaultTTL, cipher: sealed.combined)
        log.info("Flushing queue...")
        tryFlush()
    }

    // MARK: Private
    private enum RunState { case stopped, running }
    private var state: RunState = .stopped

    // Identity (Curve25519)
    internal lazy var privateKey: Curve25519.KeyAgreement.PrivateKey = {
        if let data = KeychainHelper.load(tag: "eqmesh.identity") {
            return try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let k = Curve25519.KeyAgreement.PrivateKey()
        KeychainHelper.save(k.rawRepresentation, tag: "eqmesh.identity")
        return k
    }()
    var myID: UUID { UUID(uuid: privateKey.publicKey.rawRepresentation.sha256Prefix16()) }

    // MPC plumbing
    internal let myPeer = MCPeerID(displayName: UIDevice.current.name)
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: myPeer, discoveryInfo: nil, serviceType: MeshConfig.serviceType)
    private lazy var browser = MCNearbyServiceBrowser(
        peer: myPeer, serviceType: MeshConfig.serviceType)
    internal var sessions: [MCPeerID: MCSession] = [:]

    // Route table + sequence tracking
    private var seqNo: UInt32 = 0
    private var bestNextHop: [UUID: MCPeerID] = [:]

    // Persistence
    private var context: ModelContext!

    // Timers & log
    private var beaconTimer: DispatchSourceTimer?
    private let log = Logger(subsystem: "mesh", category: "core")
    private var lastSeq: [UUID: UInt32] = [:]

    // MARK: Beaconing
    private func runBeaconTimer() {
        beaconTimer?.cancel()
        beaconTimer = DispatchSource.makeTimerSource()
        beaconTimer?.schedule(deadline: .now(), repeating: MeshConfig.beaconInterval)
        beaconTimer?.setEventHandler { [weak self] in self?.broadcastBeacon() }
        beaconTimer?.resume()
    }

    private func broadcastBeacon() {
        guard !sessions.isEmpty else { return }
        seqNo &+= 1
        let beacon = Beacon(origin: myID, seqNo: seqNo, ttl: MeshConfig.defaultTTL, hop: 0)
        guard let header = try? JSONEncoder().encode(beacon) else { return }
        let packet = buildPacket(type: .frame, header: header)
        for session in sessions.values {
            try? session.send(packet, toPeers: session.connectedPeers, with: .unreliable)
        }
    }

    // MARK: Frame queue
    private func queueFrame(dest: UUID, ttl: UInt8, cipher: Data) {
        let frameID = dest.uuidString + "|" + String(seqNo)
        let entity = FrameEntity(
            frameID: frameID, sourceID: myID, destID: dest, ttl: ttl, cipherBlob: cipher)
        context.insert(entity)
        try? context.save()
    }

    private func tryFlush() {
        let fetch = FetchDescriptor<FrameEntity>(predicate: #Predicate { $0.ttlRemaining > 0 })
        log.info("Checking for frames to send...")
        guard let frames = try? context.fetch(fetch) else { return }
        log.info("Frame count: \(frames.count)")

        for frame in frames {
            log.info("Frame to \(frame.destID)...")

            // Build header & packet once
            let header = FrameHeader(
                origin: myID,
                dest: frame.destID,
                ttl: frame.ttlRemaining,
                seq: frame.createdAt.timeIntervalSince1970.bitPattern)
            guard let headerData = try? JSONEncoder().encode(header) else { continue }
            let packet = buildPacket(
                type: .frame,
                header: headerData,
                body: frame.cipherBlob)

            // Pick sessions: either the single hop, or *all* sessions
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
                    log.info("Sending frame via \(sess.myPeerID.displayName)…")
                    try sess.send(packet, toPeers: sess.connectedPeers, with: .reliable)
                } catch {
                    log.error("send error: \(error, privacy: .public)")
                }
            }

            // Decrement TTL & cleanup
            frame.ttlRemaining &-= 1
            if frame.ttlRemaining == 0 {
                context.delete(frame)
            }
        }
        try? context.save()
    }

    // MARK: Contact Card
    var myContactCard: ContactCard {
        let pubKeyData = privateKey.publicKey.rawRepresentation
        let nickname = UIDevice.current.name
        return ContactCard(
            uuid: myID,
            nickname: nickname,
            pubKey: pubKeyData)
    }

    // MARK: Crypto helper
    private func deriveSymmetricKey(to dest: UUID) throws -> SymmetricKey {
        log.info("Lookup public key for \(dest)")
        guard let keyData = KeyStore.pubKey(for: dest, in: context) else {
            log.error("Public key for \(dest) not found")
            throw MeshError.pubKeyMissing  // Signal "no key yet"
        }
        log.info("Creating symmetric key for \(dest)...")
        let peerPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyData)
        log.info("Creating shared secret...")
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peerPub)
        log.info("Derived symmetric key...")
        let hkdfSecret = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(), sharedInfo: Data(),
            outputByteCount: 32)
        return hkdfSecret
    }

    /*
    private func handleBeacon(_ hdr: Data, via peer: MCPeerID) {
        guard var b = try? JSONDecoder().decode(Beacon.self, from: hdr) else { return }
    
        log.info("Handling beacon from \(peer.displayName)")
    
        if let seen = lastSeq[b.origin], seen >= b.seqNo { return }   // duplicate / old
        lastSeq[b.origin] = b.seqNo
        bestNextHop[b.origin] = peer
    
        guard b.ttl > 1 else { return }  // stop here
        b.ttl &-= 1; b.hop &+= 1
        guard let rebroadcast = try? JSONEncoder().encode(b) else { return }
    
        let pkt = buildPacket(type: .beacon, header: rebroadcast)
        for session in sessions.values where session != sessions[peer] {
            try? session.send(pkt, toPeers: session.connectedPeers, with: .unreliable)
        }
    }
    */

    private func handleFrame(hdr: Data, cipher: Data, via peer: MCPeerID) {
        log.info("Trying to decode frame header")
        log.info("Raw header JSON: \(String(data: hdr, encoding: .utf8) ?? "<not UTF8>")")
        guard var h = try? JSONDecoder().decode(FrameHeader.self, from: hdr) else { return }

        log.info("Handling frame from \(peer.displayName)")

        if h.dest == myID {
            guard let symm = try? deriveSymmetricKey(to: h.origin) else {
                log.warning("Could not derive symmetric key")
                return
            }

            guard let box = try? ChaChaPoly.SealedBox(combined: cipher),
                let clear = try? ChaChaPoly.open(box, using: symm)
            else { return }

            let text = String(data: clear, encoding: .utf8) ?? "<bin>"
            self.lastInbound = (from: h.dest, text)
            log.info("📩 From \(peer.displayName): \(text)")
            sendAck(for: h, via: peer)
        } else {
            guard h.ttl > 1 else { return }
            h.ttl &-= 1
            let nextPacket = buildPacket(
                type: .frame,
                header: try! JSONEncoder().encode(h),
                body: cipher)

            if let hop = bestNextHop[h.dest],
                let sess = sessions[hop]
            {
                try? sess.send(nextPacket, toPeers: [hop], with: .reliable)
            } else {
                for sess in sessions.values {
                    try? sess.send(nextPacket, toPeers: sess.connectedPeers, with: .reliable)
                }
            }
        }
    }

    private func sendAck(for header: FrameHeader, via peer: MCPeerID) {
        var ackID = withUnsafeBytes(of: header.seq.bigEndian, Array.init)  // 8‑byte ID
        let packet = buildPacket(type: .ack, header: Data(ackID))
        sessions[peer].map { try? $0.send(packet, toPeers: [$0.myPeerID], with: .reliable) }
    }

    private func handleAck(_ hdr: Data, via _: MCPeerID) {
        guard hdr.count == 8 else { return }
        let seq = UInt64(bigEndian: hdr.withUnsafeBytes { $0.load(as: UInt64.self) })
        let id = sessions.values.flatMap { $0.connectedPeers }.first?.displayName ?? ""
        // TODO: look up FrameEntity with matching seq and delete it
        // TODO: store seq in FrameEntity when queueing
    }
}

@MainActor
extension MeshService: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate,
    MCSessionDelegate
{
    func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard sessions.count < MeshConfig.maxNeighbours else { return }
        let ctx = privateKey.publicKey.rawRepresentation  // send pubKey as context
        browser.invitePeer(peerID, to: makeSession(for: peerID), withContext: ctx, timeout: 5)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        sessions[peerID]?.disconnect()
        reachablePeers.removeAll { $0 == peerID }
        sessions[peerID] = nil
    }
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, makeSession(for: peerID))
    }

    private func makeSession(for peer: MCPeerID) -> MCSession {
        if let existing = sessions[peer] { return existing }
        let s = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        sessions[peer] = s
        reachablePeers += [peer]
        return s
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            // add only if new
            if !reachablePeers.contains(peerID) {
                reachablePeers.append(peerID)
            }
        case .notConnected:
            // remove on disconnect
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

        let rawType = data[0]
        print("[mesh] got raw type byte: 0x\(String(format: "%02X", rawType))")

        // No pointer loads, no alignment assumptions
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
