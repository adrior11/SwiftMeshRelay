//
//  PacketType.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Foundation

enum PacketType: UInt8 {          // 1‑byte discriminator
    // case beacon = 0x42            // 'B'
    case frame  = 0x46            // 'F'
    case ack    = 0x61            // 'a'
}

/// put <type><u16 headerLen><header><payload?>
func buildPacket(type: PacketType, header: Data, body: Data = .init()) -> Data {
    print(type.rawValue)
    var d = Data()
    // Discriminator
    d.append(type.rawValue)
    // Big-endian header length
    var lenBE = UInt16(header.count).bigEndian
    withUnsafeBytes(of: &lenBE) { ptr in
        d.append(contentsOf: ptr)
    }
    d.append(header)
    d.append(body)
    return d
}
