//
//  MeshContact.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
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
