//
//  AdaptiveSheet.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  iPhone과 iPad에 적응하는 모달 표시 모디파이어입니다.
//  iPhone에서는 sheet, iPad에서는 popover로 표시됩니다.
//

import SwiftUI

/// 디바이스에 따라 적응하는 모달 표시 모디파이어
struct AdaptiveSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            // iPad - Popover
            content
                .popover(isPresented: $isPresented) {
                    sheetContent()
                        .frame(minWidth: 400, minHeight: 500)
                }
        } else {
            // iPhone - Sheet
            content
                .sheet(isPresented: $isPresented) {
                    sheetContent()
                }
        }
    }
}

/// 적응형 모달 표시 익스텐션
extension View {
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(AdaptiveSheet(isPresented: isPresented, sheetContent: content))
    }
}