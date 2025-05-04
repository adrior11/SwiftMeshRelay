//
//  FrameEntity.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import SwiftData
import Foundation

@Model final class FrameEntity {
    @Attribute(.unique) var id: String
    var sourceID: UUID
    var destID: UUID
    var ttlRemaining: UInt8
    var cipherBlob: Data
    var createdAt: Date
    var expiresAt: Date
    var ackPending: Bool
    
    init(frameID: String, sourceID: UUID, destID: UUID, ttl: UInt8, cipherBlob: Data, lifetime: TimeInterval = 84_400) {
        self.id = frameID
        self.sourceID = sourceID
        self.destID = destID
        self.ttlRemaining = ttl
        self.cipherBlob = cipherBlob
        self.createdAt = Date.now
        self.expiresAt = Date.now.addingTimeInterval(lifetime)
        self.ackPending = true
    }
}
