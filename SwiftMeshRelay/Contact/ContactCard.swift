//
//  ContactCard.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation

/// One peer’s identity
struct ContactCard: Codable, Hashable, Sendable {
    var uuid: UUID
    var nickname: String
    var pubKey: Data      // 32 bytes Curve25519
}
