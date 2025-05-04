//
//  KeychainHelper.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Security
import Foundation

enum KeychainHelper {
    static func save(_ data: Data, tag: String) {
        let query: [String: Any] = [kSecValueData as String: data,
                                     kSecClass as String: kSecClassKey,
                                     kSecAttrApplicationTag as String: tag,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    static func load(tag: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassKey,
                                     kSecAttrApplicationTag as String: tag,
                                     kSecReturnData as String: kCFBooleanTrue!,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
}
