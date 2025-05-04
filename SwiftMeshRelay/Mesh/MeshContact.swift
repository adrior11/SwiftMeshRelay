//
//  MeshContact.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import SwiftData
import Foundation
import CryptoKit

@Model final class MeshContact {
    @Attribute(.unique) var uuid: UUID
    var nickname: String
    var pubKey: Data?   // X25519 public key

    init(uuid: UUID, nickname: String, pubKey: Data? = nil) {
        self.uuid = uuid
        self.nickname = nickname
        self.pubKey = pubKey
    }
}
