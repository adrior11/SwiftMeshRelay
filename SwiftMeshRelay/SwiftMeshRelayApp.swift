//
//  SwiftMeshRelay.swift
//  SwiftMeshRelay
//
//  Created by Schneider, Adrian on 03.05.25.
//

import SwiftUI
import SwiftData

@main
struct SwiftMeshRelayApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FrameEntity.self,
            MeshContact.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MeshDebugView()
                .onAppear {
                    print("Starting mesh service...")
                    MeshService.shared.configure(container: sharedModelContainer)
                    MeshService.shared.start()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
