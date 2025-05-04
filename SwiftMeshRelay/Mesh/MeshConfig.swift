//
//  MeshConfig.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import Foundation

struct MeshConfig {
    static let serviceType = "nisample"
    static let beaconInterval: TimeInterval = 2     // seconds
    static let maxNeighbours = 7                    // MPC hard‑limit – 1
    static let defaultTTL: UInt8 = 8                // hop budget
}
