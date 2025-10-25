//
//  ClothIQApp.swift
//  ClothIQ
//
//  Created by EUN YEON on 10/22/25.
//
//  Description:
//  ClothIQ 앱의 진입점입니다.
//  SwiftData ModelContainer를 설정하고 앱의 생명주기를 관리합니다.
//

import SwiftUI
import SwiftData

@main
struct ClothIQApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ClothingItemModel.self,
            MeasurementModel.self,
            TagModel.self
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
            AppContainerView()
        }
        .modelContainer(sharedModelContainer)
    }
}
