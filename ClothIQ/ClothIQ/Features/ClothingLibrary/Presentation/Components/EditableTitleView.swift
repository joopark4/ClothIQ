//
//  EditableTitleView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  인라인 편집 가능한 타이틀 뷰입니다.
//  탭하면 TextField로 전환되어 타이틀을 수정할 수 있습니다.
//
//  Key Features:
//  - 탭하여 편집 모드 진입
//  - 자동 포커스 및 키보드 표시
//  - 50자 제한
//  - 완료 시 자동 저장
//

import SwiftUI

/// 인라인 편집 가능한 타이틀 뷰
///
/// ## Usage
/// ```swift
/// EditableTitleView(
///     title: $item.title,
///     placeholder: "의류 아이템 이름",
///     onSave: { newTitle in
///         // 저장 로직
///     }
/// )
/// ```
struct EditableTitleView: View {

    // MARK: - Properties

    /// 타이틀 텍스트 (바인딩)
    @Binding var title: String?

    /// placeholder 텍스트
    let placeholder: String

    /// 저장 콜백
    let onSave: ((String?) -> Void)?

    /// 편집 모드 여부
    @State private var isEditing: Bool = false

    /// 임시 텍스트 (편집 중)
    @State private var editingText: String = ""

    /// TextField 포커스 상태
    @SwiftUI.FocusState private var isFocused: Bool

    // MARK: - Constants

    private let maxLength: Int = 50

    // MARK: - Initialization

    init(
        title: Binding<String?>,
        placeholder: String = "의류 아이템 이름",
        onSave: ((String?) -> Void)? = nil
    ) {
        self._title = title
        self.placeholder = placeholder
        self.onSave = onSave
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                // 편집 모드: TextField
                TextField(placeholder, text: $editingText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .focused($isFocused)
                    .onSubmit {
                        saveAndExitEditMode()
                    }
                    .onChange(of: editingText) { oldValue, newValue in
                        // 글자 수 제한
                        if newValue.count > maxLength {
                            editingText = String(newValue.prefix(maxLength))
                        }
                    }
                    .textFieldStyle(.plain)

                // 완료 버튼
                Button {
                    saveAndExitEditMode()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                // 취소 버튼
                Button {
                    cancelEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)

            } else {
                // 일반 모드: 타이틀 표시
                Button {
                    startEditing()
                } label: {
                    HStack(spacing: 4) {
                        Text(displayTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.body)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }

    // MARK: - Computed Properties

    /// 표시할 타이틀 (비어있으면 placeholder)
    private var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return placeholder
    }

    // MARK: - Actions

    /// 편집 모드 시작
    private func startEditing() {
        editingText = title ?? ""
        isEditing = true

        // TextField에 포커스 (약간 딜레이)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFocused = true
        }
    }

    /// 저장하고 편집 모드 종료
    private func saveAndExitEditMode() {
        let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 빈 문자열은 nil로 저장
        let newTitle = trimmedText.isEmpty ? nil : trimmedText

        title = newTitle
        onSave?(newTitle)

        isEditing = false
        isFocused = false
        editingText = ""
    }

    /// 편집 취소
    private func cancelEditing() {
        editingText = ""
        isEditing = false
        isFocused = false
    }
}

// MARK: - Previews

#Preview("Empty Title") {
    @Previewable @State var title: String? = nil

    VStack {
        EditableTitleView(
            title: $title,
            placeholder: "의류 아이템 이름"
        ) { newTitle in
            print("Saved: \(newTitle ?? "nil")")
        }
        .padding()

        Divider()

        Text("현재 타이틀: \(title ?? "없음")")
            .foregroundStyle(.secondary)
            .padding()
    }
}

#Preview("With Title") {
    @Previewable @State var title: String? = "검은색 긴팔 티셔츠"

    VStack {
        EditableTitleView(
            title: $title,
            placeholder: "의류 아이템 이름"
        ) { newTitle in
            print("Saved: \(newTitle ?? "nil")")
        }
        .padding()

        Divider()

        Text("현재 타이틀: \(title ?? "없음")")
            .foregroundStyle(.secondary)
            .padding()
    }
}
