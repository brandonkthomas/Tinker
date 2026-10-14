//
//  SettingControls.swift
//  Tinker
//

import SwiftUI
import UniformTypeIdentifiers

/// Picks the control that matches the setting's catalog entry.
struct SettingControlView: View {
    let item: SettingItem

    var body: some View {
        switch item.definition.control {
        case .toggle:
            ToggleControl(item: item)
        case .choice(let options, _):
            ChoiceControl(item: item, options: options)
        case .number(let range, let step, let unit, _):
            NumberControl(item: item, range: range, step: step, unit: unit)
        case .text(let placeholder):
            TextControl(item: item, placeholder: placeholder)
        case .status(_, _, let actions):
            StatusControl(item: item, actions: actions)
        case .folder:
            FolderControl(item: item)
        }
    }
}

/// Reports a yes/no state and offers the buttons that apply to it.
struct StatusControl: View {
    let item: SettingItem
    let actions: [SettingControl.StatusAction]

    var body: some View {
        HStack(spacing: 8) {
            StatusText(
                text: item.currentDisplayText,
                isAsExpected: item.definition.profileValue.map(item.matches)
            )
            ForEach(actions, id: \.self) { action in
                if isOffered(action) {
                    Button(action.title) {
                        item.apply(.bool(action.value))
                    }
                }
            }
        }
    }

    private func isOffered(_ action: SettingControl.StatusAction) -> Bool {
        switch action.when {
        case .always: true
        case .on: item.statusIsOn == true
        case .off: item.statusIsOn == false
        }
    }
}

struct StatusText: View {
    let text: String
    /// Whether the state is the recommended one, when there is a recommendation.
    let isAsExpected: Bool?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .foregroundStyle(.secondary)
    }

    private var symbol: String {
        switch isAsExpected {
        case true: "checkmark.circle.fill"
        case false: "exclamationmark.circle.fill"
        default: "circle"
        }
    }

    private var color: Color {
        switch isAsExpected {
        case true: .green
        case false: .orange
        default: .secondary
        }
    }
}

/// Picks one of the standard folders, or any folder through the file dialog.
struct FolderControl: View {
    let item: SettingItem

    @State private var isChoosingFolder = false

    var body: some View {
        Menu(item.currentDisplayText) {
            Button("Home") { item.text = FinderWindowTarget.home }
            Button("Desktop") { item.text = FinderWindowTarget.desktop }
            Button("Documents") { item.text = FinderWindowTarget.documents }
            Divider()
            Button("Choose Folder…") { isChoosingFolder = true }
        }
        .fixedSize()
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                item.text = url.absoluteString
            }
        }
    }
}

struct ToggleControl: View {
    @Bindable var item: SettingItem

    var body: some View {
        Toggle(item.definition.title, isOn: $item.isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            // The compact switch a grouped Form uses.
            .controlSize(.mini)
    }
}

struct ChoiceControl: View {
    @Bindable var item: SettingItem
    let options: [SettingControl.Option]

    var body: some View {
        Picker(item.definition.title, selection: $item.selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label)
                    .tag(option.value.coerced(to: item.definition.valueType))
            }
            UnlistedChoice(selection: item.selection, options: options, valueType: item.definition.valueType)
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// An extra menu row for a stored value the catalog does not list, so the
/// picker always has a row matching the current selection.
struct UnlistedChoice: View {
    let selection: PreferenceValue?
    let options: [SettingControl.Option]
    let valueType: ValueType

    var body: some View {
        if !options.contains(where: { $0.value.coerced(to: valueType) == selection }) {
            Divider()
            if let selection {
                Text(verbatim: selection.displayText).tag(PreferenceValue?.some(selection))
            } else {
                Text("System Default").tag(PreferenceValue?.none)
            }
        }
    }
}

struct NumberControl: View {
    let item: SettingItem
    let range: ClosedRange<Double>
    let step: Double
    let unit: String?

    /// The slider position while dragging. Written to the preference when the drag ends.
    @State private var draft: Double
    @State private var isDragging = false

    init(item: SettingItem, range: ClosedRange<Double>, step: Double, unit: String?) {
        self.item = item
        self.range = range
        self.step = step
        self.unit = unit
        self.draft = item.number ?? range.lowerBound
    }

    var body: some View {
        HStack(spacing: 8) {
            NumberValueText(value: isDragging || item.number != nil ? snapped(draft) : nil, unit: unit)
            Slider(value: $draft, in: range) {
                Text(item.definition.title)
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    item.number = snapped(draft)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .onChange(of: item.number) { _, newValue in
            draft = newValue ?? range.lowerBound
        }
    }

    private func snapped(_ value: Double) -> Double {
        let snappedValue = (value / step).rounded() * step
        return min(max(snappedValue, range.lowerBound), range.upperBound)
    }
}

struct NumberValueText: View {
    /// `nil` when no value is stored and the system default is not known.
    let value: Double?
    let unit: String?

    var body: some View {
        HStack(spacing: 2) {
            if let value {
                Text(value, format: .number.precision(.fractionLength(0...2)))
                if let unit {
                    Text(verbatim: unit)
                }
            } else {
                Text("Default")
            }
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

struct TextControl: View {
    let item: SettingItem
    let placeholder: String?

    /// What is typed so far. Written to the preference on Return or when the field loses focus.
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(item: SettingItem, placeholder: String?) {
        self.item = item
        self.placeholder = placeholder
        self.draft = item.text
    }

    var body: some View {
        TextField(item.definition.title, text: $draft, prompt: placeholder.map { Text(verbatim: $0) })
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 260)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: item.text) { _, newValue in
                draft = newValue
            }
    }

    private func commit() {
        if draft != item.text {
            item.text = draft
        }
    }
}
