//
//  ContactCard.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Foundation

/// One peer’s identity
struct ContactCard: Codable, Hashable, Sendable {
    var uuid: UUID
    var nickname: String
    var pubKey: Data      // 32 bytes Curve25519
}
