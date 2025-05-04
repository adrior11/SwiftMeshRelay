//
//  FrameHeader.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation

struct FrameHeader: Codable {
    var origin: UUID
    var dest: UUID
    var ttl: UInt8
    var seq: UInt64
}
