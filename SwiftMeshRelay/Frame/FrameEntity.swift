//
//  FrameEntity.swift
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

import Foundation
import SwiftData

@Model final class FrameEntity {
    @Attribute(.unique) var id: String
    var sourceID: UUID
    var destID: UUID
    var ttlRemaining: UInt8
    var cipherBlob: Data
    var createdAt: Date
    var expiresAt: Date
    var ackPending: Bool

    init(
        frameID: String, sourceID: UUID, destID: UUID, ttl: UInt8, cipherBlob: Data,
        lifetime: TimeInterval = 84_400
    ) {
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
