//
//  FrameHeader.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Foundation

struct FrameHeader: Codable {
    var origin: UUID
    var dest: UUID
    var ttl: UInt8
    var seq: UInt64
}
