//
//  MeshConfig.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//  Copyright © 2025 Adrian Schneider
//  Licensed under the MIT License – see LICENSE file in project root.
//

import Foundation

struct MeshConfig {
    static let serviceType = "nisample"
    static let beaconInterval: TimeInterval = 2     // seconds
    static let maxNeighbours = 7                    // MPC hard‑limit – 1
    static let defaultTTL: UInt8 = 8                // hop budget
}
