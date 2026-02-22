//
//  AdaptiveMeasurementSheet.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  측정 화면용 적응형 모달 표시 모디파이어입니다.
//

import SwiftUI

/// 측정 화면용 적응형 모달 표시 모디파이어
struct AdaptiveMeasurementSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    @ViewBuilder let sheetContent: () -> SheetContent

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            // iPad - Popover로 표시
            content
                .popover(isPresented: $isPresented) {
                    sheetContent()
                }
        } else {
            // iPhone - Sheet로 표시
            content
                .sheet(isPresented: $isPresented) {
                    sheetContent()
                }
        }
    }
}