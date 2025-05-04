//
//  Beacon.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation

struct Beacon: Codable, Hashable {
    var origin: UUID
    var seqNo: UInt32
    var ttl: UInt8
    var hop: UInt8
}
