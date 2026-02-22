//
//  ContentView.swift
//  ClothIQ
//
//  Created by EUN YEON on 10/22/25.
//
//  Description:
//  메인 화면으로 ClothingLibraryView를 표시합니다.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ClothingLibraryView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ClothingItemModel.self, inMemory: true)
}
