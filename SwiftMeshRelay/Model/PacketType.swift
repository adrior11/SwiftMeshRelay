//
//  PacketType.swift
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

enum PacketType: UInt8 {  // 1‑byte discriminator
    // case beacon = 0x42  // 'B'
    case frame = 0x46  // 'F'
    case ack = 0x61  // 'a'
}

/// put <type><u16 headerLen><header><payload?>
func buildPacket(type: PacketType, header: Data, body: Data = .init()) -> Data {
    print(type.rawValue)
    var d = Data()
    d.append(type.rawValue)  // Discriminator
    var lenBE = UInt16(header.count).bigEndian  // Big-endian header length
    withUnsafeBytes(of: &lenBE) { ptr in
        d.append(contentsOf: ptr)
    }
    d.append(header)
    d.append(body)
    return d
}
