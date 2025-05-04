//
//  Beacon.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Foundation

struct Beacon: Codable, Hashable {
    var origin: UUID
    var seqNo: UInt32
    var ttl: UInt8
    var hop: UInt8
}
