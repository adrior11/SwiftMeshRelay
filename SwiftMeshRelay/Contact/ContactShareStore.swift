//
//  ContactShareStore.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import SwiftData
import Foundation

enum ContactShareStore {
    @MainActor
    static func store(_ card: ContactCard, in context: ModelContext) {
        let predicate = #Predicate<MeshContact> { $0.uuid == card.uuid }
        if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.pubKey   = card.pubKey
            existing.nickname = card.nickname
        } else {
            context.insert(MeshContact(uuid: card.uuid,
                                       nickname: card.nickname,
                                       pubKey: card.pubKey))
        }
        try? context.save()
    }
}
