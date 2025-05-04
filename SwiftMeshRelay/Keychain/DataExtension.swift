//
//  DataExtension.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation
import CryptoKit

extension Data {
    func sha256Prefix16() -> uuid_t {
        let digest = SHA256.hash(data: self)
        let bytes  = Array(digest)  // Digest → [UInt8]
        return (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],
                bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],
                bytes[12],bytes[13],bytes[14],bytes[15])
    }
}
