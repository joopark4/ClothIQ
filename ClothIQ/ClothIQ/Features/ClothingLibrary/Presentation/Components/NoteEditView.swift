//
//  NoteEditView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  메모를 편집하는 화면 컴포넌트입니다.
//  텍스트 에디터와 저장/취소 기능을 제공합니다.
//

import SwiftUI

/// 메모 편집 화면
struct NoteEditView: View {
    @Binding var note: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $note)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding()

                Spacer()
            }
            .navigationTitle("메모 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        onSave(note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
