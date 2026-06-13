import AppKit
import PaddlrCore
import SwiftUI

struct PermissionStatusRowView: View {
    let isTrusted: Bool
    let trustedText: String
    let neededText: String
    let buttonTitle: String
    let systemImage: String
    let helpText: String
    let detailText: String
    var isButtonEnabled = true
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isTrusted ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                Text(isTrusted ? trustedText : neededText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !isTrusted {
                Button(action: action) {
                    Label(buttonTitle, systemImage: systemImage)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isButtonEnabled)
                .help(helpText)

                Text(detailText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PaddleMappingRow: View {
    @ObservedObject var model: MenuBarMapperModel
    let paddle: Paddle
    let isPendingChange: Bool

    private var isCapturing: Bool {
        model.capturingPaddle == paddle
    }

    private var action: PaddleAction {
        model.selectedProfileAction(for: paddle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(paddle.displayName)
                    .font(.headline)
                Spacer()
                bindingMenu
            }

            HStack(alignment: .bottom) {
                Button(isCapturing ? "Waiting" : "Capture") {
                    if isCapturing {
                        model.cancelKeyCapture()
                    } else {
                        model.startKeyCapture(for: paddle)
                    }
                }
                .buttonStyle(.bordered)

                if isCapturing {
                    Button("Cancel") {
                        model.cancelKeyCapture()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
                paddleStateBadge
            }
        }
        .padding(8)
        .background(isPendingChange ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPendingChange ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var bindingMenu: some View {
        BindingMenuButton(
            title: action.displayName,
            isDisabledSelected: isCurrentDisabled,
            selectedKey: currentPresetKey,
            onDisabled: {
                model.setAction(.disabled, for: paddle)
            },
            onKey: { key in
                model.setSyntheticKey(key, for: paddle)
            }
        )
        .frame(width: 128, height: 22, alignment: .trailing)
    }

    private var isCurrentDisabled: Bool {
        if case .disabled = action {
            return true
        }
        return false
    }

    private var currentPresetKey: SyntheticKey? {
        guard case .keyboard(let mapping) = action else {
            return nil
        }

        return SyntheticKey.allCases.first { key in
            mapping.keyCode == key.keyCode && mapping.modifierFlagsRawValue == key.keyboardMapping.modifierFlagsRawValue
        }
    }

    private var paddleStateBadge: some View {
        HStack(spacing: 5) {
            PaddleStateIndicator(isPressed: model.isPressed(paddle))
            Text(model.isPressed(paddle) ? "Pressed" : "Released")
                .font(.caption)
                .foregroundColor(model.isPressed(paddle) ? .accentColor : .secondary)
        }
    }
}

struct ControllerPickerButton: NSViewRepresentable {
    let controllers: [MenuBarControllerSelection]
    let selectedIdentifier: String?
    let onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectController(_:))
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.removeAllItems()

        if controllers.isEmpty {
            button.addItem(withTitle: "No Controller")
            button.isEnabled = false
            return
        }

        button.isEnabled = true
        for controller in controllers {
            let item = NSMenuItem(title: controller.title, action: nil, keyEquivalent: "")
            item.representedObject = controller.identifier
            button.menu?.addItem(item)
        }

        if let selectedIdentifier,
           let selectedIndex = controllers.firstIndex(where: { $0.identifier == selectedIdentifier }) {
            button.selectItem(at: selectedIndex)
        } else {
            button.selectItem(at: 0)
        }
    }

    final class Coordinator: NSObject {
        var onSelect: (String?) -> Void

        init(onSelect: @escaping (String?) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectController(_ sender: NSPopUpButton) {
            onSelect(sender.selectedItem?.representedObject as? String)
        }
    }
}

struct ProfilePickerButton: NSViewRepresentable {
    let profiles: [MappingProfile]
    let selectedProfileID: UUID
    let onSelect: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectProfile(_:))
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.removeAllItems()

        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            button.menu?.addItem(item)
        }

        if let selectedIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            button.selectItem(at: selectedIndex)
        } else if !profiles.isEmpty {
            button.selectItem(at: 0)
        }
    }

    final class Coordinator: NSObject {
        var onSelect: (UUID) -> Void

        init(onSelect: @escaping (UUID) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectProfile(_ sender: NSPopUpButton) {
            guard
                let uuidString = sender.selectedItem?.representedObject as? String,
                let profileID = UUID(uuidString: uuidString)
            else {
                return
            }

            onSelect(profileID)
        }
    }
}

struct AppPickerButton: NSViewRepresentable {
    let apps: [AppSelection]
    let selectedBundleIdentifier: String?
    let onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectApp(_:))
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect

        if context.coordinator.apps != apps {
            button.removeAllItems()

            for app in apps {
                let item = NSMenuItem(title: app.appName, action: nil, keyEquivalent: "")
                item.representedObject = app.bundleIdentifier
                item.image = Self.icon(for: app)
                button.menu?.addItem(item)
            }

            context.coordinator.apps = apps
            context.coordinator.selectedBundleIdentifier = nil
        }

        let selectedIdentifier = selectedBundleIdentifier ?? apps.first?.bundleIdentifier
        guard context.coordinator.selectedBundleIdentifier != selectedIdentifier else {
            return
        }

        if let selectedIndex = apps.firstIndex(where: { $0.bundleIdentifier == selectedIdentifier }) {
            button.selectItem(at: selectedIndex)
            context.coordinator.selectedBundleIdentifier = selectedIdentifier
        } else if !apps.isEmpty {
            button.selectItem(at: 0)
            context.coordinator.selectedBundleIdentifier = apps[0].bundleIdentifier
        } else {
            context.coordinator.selectedBundleIdentifier = nil
        }
    }

    private static let defaultIconCacheKey = "__default_app_icon__"
    private static var iconCache: [String: NSImage] = [:]

    private static func icon(for app: AppSelection) -> NSImage? {
        let cacheKey = app.isDefault ? defaultIconCacheKey : app.bundleIdentifier
        if let cachedImage = iconCache[cacheKey] {
            return cachedImage
        }

        let image: NSImage?
        if
            !app.isDefault,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        {
            image = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let defaultImage = NSImage(systemSymbolName: "app", accessibilityDescription: "App") {
            defaultImage.isTemplate = true
            image = defaultImage
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }

        let resizedImage = image?.copy() as? NSImage
        resizedImage?.size = NSSize(width: 16, height: 16)
        if let resizedImage {
            iconCache[cacheKey] = resizedImage
        }
        return resizedImage
    }

    final class Coordinator: NSObject {
        var onSelect: (String?) -> Void
        var apps: [AppSelection] = []
        var selectedBundleIdentifier: String?

        init(onSelect: @escaping (String?) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectApp(_ sender: NSPopUpButton) {
            onSelect(sender.selectedItem?.representedObject as? String)
        }
    }
}

struct BindingMenuButton: NSViewRepresentable {
    let title: String
    let isDisabledSelected: Bool
    let selectedKey: SyntheticKey?
    let onDisabled: () -> Void
    let onKey: (SyntheticKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDisabled: onDisabled, onKey: onKey)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.alignment = .right
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onDisabled = onDisabled
        context.coordinator.onKey = onKey
        context.coordinator.isDisabledSelected = isDisabledSelected
        context.coordinator.selectedKey = selectedKey
        button.title = "\(title) ⌄"
    }

    final class Coordinator: NSObject {
        var onDisabled: () -> Void
        var onKey: (SyntheticKey) -> Void
        var isDisabledSelected = false
        var selectedKey: SyntheticKey?

        init(onDisabled: @escaping () -> Void, onKey: @escaping (SyntheticKey) -> Void) {
            self.onDisabled = onDisabled
            self.onKey = onKey
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            let disabledItem = NSMenuItem(title: "Disabled", action: #selector(selectMenuItem(_:)), keyEquivalent: "")
            disabledItem.target = self
            disabledItem.representedObject = "__disabled__"
            disabledItem.state = isDisabledSelected ? .on : .off
            menu.addItem(disabledItem)
            menu.addItem(.separator())

            for key in SyntheticKey.allCases {
                let item = NSMenuItem(title: key.displayName, action: #selector(selectMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = key.rawValue
                item.state = selectedKey == key ? .on : .off
                menu.addItem(item)
            }

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }

        @objc private func selectMenuItem(_ item: NSMenuItem) {
            guard let representedObject = item.representedObject as? String else {
                return
            }

            if representedObject == "__disabled__" {
                onDisabled()
            } else if let key = SyntheticKey(rawValue: representedObject) {
                onKey(key)
            }
        }
    }
}

struct PaddleStateIndicator: View {
    let isPressed: Bool

    var body: some View {
        Circle()
            .fill(isPressed ? Color.accentColor : Color.secondary.opacity(0.35))
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(isPressed ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.25), lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.12), value: isPressed)
    }
}
