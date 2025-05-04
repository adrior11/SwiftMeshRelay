//
//  KeyStore.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation
import SwiftData

enum KeyStore {
    @MainActor
    static func pubKey(for uuid: UUID, in ctx: ModelContext) -> Data? {
        let req = FetchDescriptor<MeshContact>(predicate: #Predicate { $0.uuid == uuid })
        return try? ctx.fetch(req).first?.pubKey
    }
}
