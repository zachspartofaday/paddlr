import AppKit
import PaddlrCore
import SwiftUI
import UniformTypeIdentifiers

private struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct AppSelection: Identifiable, Hashable {
    static let defaultBundleIdentifier = "__app_default__"

    var bundleIdentifier: String
    var appName: String
    var isDefault: Bool = false

    var id: String {
        bundleIdentifier
    }

    static var appDefault: AppSelection {
        AppSelection(bundleIdentifier: defaultBundleIdentifier, appName: "Default", isDefault: true)
    }
}

private enum ProfileAssignmentTarget: Equatable {
    case defaultApplication(controllerIdentifier: String?)
    case application(bundleIdentifier: String, appName: String, controllerIdentifier: String?)
}

private struct PendingMappingSave: Equatable {
    var profileID: UUID
    var target: ProfileAssignmentTarget
}

struct MappingPanelView: View {
    @ObservedObject var model: MenuBarMapperModel
    let showsDiagnosticHelperText: Bool
    let onContentSizeChange: (NSSize) -> Void
    @State private var isRecentEventsExpanded = false
    @State private var selectedAppBundleIdentifier: String? = AppSelection.defaultBundleIdentifier
    @State private var isCreatingProfile = false
    @State private var isRenamingProfile = false
    @State private var draftProfileName = ""
    @State private var isRenamingController = false
    @State private var draftControllerName = ""
    @State private var pendingMappingSave: PendingMappingSave?
    @State private var pendingChangedPaddles: Set<Paddle> = []

    static let selectorWidth: CGFloat = 260

    static let preferredContentSize = NSSize(width: 520, height: 690)

    init(
        model: MenuBarMapperModel,
        showsDiagnosticHelperText: Bool = false,
        onContentSizeChange: @escaping (NSSize) -> Void = { _ in }
    ) {
        self.model = model
        self.showsDiagnosticHelperText = showsDiagnosticHelperText
        self.onContentSizeChange = onContentSizeChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controllerSection
            currentAppSection
            if selectedApplicationOutputEnabled {
                profileSection
                Divider()
                mappingsSection
                Divider()
            }
            eventLogSection
            footer
        }
        .padding(16)
        .frame(width: Self.preferredContentSize.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(contentSizeReader)
        .onPreferenceChange(ContentSizePreferenceKey.self) { size in
            guard size != .zero else {
                return
            }

            onContentSizeChange(NSSize(width: Self.preferredContentSize.width, height: ceil(size.height)))
        }
        .onAppear {
            selectDefaultAppIfNeeded()
            syncProfileForSelectedApplication()
        }
        .onChange(of: model.frontmostApplication?.ruleKey) { _, _ in
            selectDefaultAppIfNeeded()
        }
        .onChange(of: selectedAppBundleIdentifier) { _, _ in
            syncProfileForSelectedApplication()
        }
        .onChange(of: model.selectedControllerIdentifier) { _, _ in
            syncProfileForSelectedApplication()
        }
        .onChange(of: model.mappingChangeRevision) { _, _ in
            guard !model.lastChangedPaddles.isEmpty else {
                clearPendingMappingChanges()
                return
            }

            if let target = currentProfileAssignmentTarget {
                pendingMappingSave = PendingMappingSave(profileID: model.selectedProfileID, target: target)
            }
            pendingChangedPaddles.formUnion(model.lastChangedPaddles)
        }
    }

    private var contentSizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentSizePreferenceKey.self, value: proxy.size)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paddlr")
                    .font(.title2)
                    .fontWeight(.semibold)
                controllerStatusRow
                accessibilityStatusRow
                controllerInputAccessStatusRow
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Keyboard output", isOn: $model.outputEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle())

                if showsDiagnosticHelperText {
                    Text(outputDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150, alignment: .trailing)
                }
            }
        }
    }

    private var controllerSection: some View {
        ControllerSectionView(
            controllers: model.connectedControllerSelections,
            selectedIdentifier: model.selectedControllerIdentifier,
            selectedControllerExists: model.selectedControllerSelection != nil,
            canPinSelectedController: model.selectedControllerCanPin,
            isSelectedControllerPinned: model.selectedControllerIsPinned,
            isRenaming: isRenamingController,
            draftName: $draftControllerName,
            onSelect: selectController,
            onBeginRename: beginRenamingController,
            onTogglePin: toggleSelectedControllerPin,
            onSaveRename: saveControllerNameEdit,
            onCancelRename: cancelControllerNameEdit
        )
    }

    private var profileSection: some View {
        ProfileSectionView(
            profiles: model.profiles,
            selectedProfileID: model.selectedProfileID,
            isDefaultProfileSelected: isDefaultProfileSelected,
            defaultProfileHasCustomMappings: defaultProfileHasCustomMappings,
            isCreatingProfile: isCreatingProfile,
            isRenamingProfile: isRenamingProfile,
            draftProfileName: $draftProfileName,
            profileDetailText: profileDetailText,
            onSelectProfile: selectProfile,
            onBeginCreate: beginCreatingProfile,
            onResetDefault: resetDefaultProfileMappings,
            onBeginRename: beginRenamingProfile,
            onConfirmDelete: confirmDeleteSelectedProfile,
            onSaveNameEdit: saveProfileNameEdit,
            onCancelNameEdit: cancelProfileNameEdit
        )
    }

    private var profileDetailText: String? {
        if showsDiagnosticHelperText {
            return diagnosticProfileDetailText
        }

        guard let selectedScopeEffectiveProfileName,
              selectedScopeEffectiveProfileID != model.selectedProfileID else {
            return nil
        }

        return "Effective profile: \(selectedScopeEffectiveProfileName)"
    }

    private var diagnosticProfileDetailText: String {
        "Effective profile: \(model.effectiveProfileName)"
    }

    private var currentAppSection: some View {
        ApplicationSectionView(
            apps: appSelections,
            selectedBundleIdentifier: selectedApp?.bundleIdentifier,
            selectedApplicationIsPinned: selectedApplicationIsPinned,
            selectedApplicationIsDefault: selectedApp?.isDefault ?? true,
            outputEnabled: selectedApplicationOutputBinding,
            onSelect: { selectedAppBundleIdentifier = $0 },
            onAdd: addApplicationRule,
            onTogglePin: toggleSelectedApplicationPin
        )
    }

    private var appSelections: [AppSelection] {
        var selections: [AppSelection] = [.appDefault]

        for app in model.pinnedApplications {
            appendAppSelection(
                AppSelection(bundleIdentifier: app.bundleIdentifier, appName: app.appName),
                to: &selections
            )
        }

        for app in model.observedApplications {
            appendAppSelection(from: app, to: &selections)
        }

        if let app = model.frontmostApplication {
            appendAppSelection(from: app, to: &selections)
        }

        for rule in model.appRules {
            appendAppSelection(
                AppSelection(bundleIdentifier: rule.bundleIdentifier, appName: rule.appName),
                to: &selections
            )
        }

        return selections
    }

    private func appendAppSelection(from app: FrontmostApplicationInfo, to selections: inout [AppSelection]) {
        guard let bundleIdentifier = app.ruleKey else {
            return
        }

        appendAppSelection(
            AppSelection(bundleIdentifier: bundleIdentifier, appName: app.displayName),
            to: &selections
        )
    }

    private func appendAppSelection(_ selection: AppSelection, to selections: inout [AppSelection]) {
        guard !selections.contains(where: { $0.bundleIdentifier == selection.bundleIdentifier }) else {
            return
        }

        selections.append(selection)
    }

    private var selectedApp: AppSelection? {
        appSelections.first(where: { $0.bundleIdentifier == selectedAppBundleIdentifier }) ?? appSelections.first
    }

    private var selectedAppRule: AppProfileRule? {
        guard let selectedApp, !selectedApp.isDefault else {
            return nil
        }

        return model.appRule(
            bundleIdentifier: selectedApp.bundleIdentifier,
            controllerIdentifier: model.selectedControllerIdentifier
        )
    }

    private var selectedApplicationIsPinned: Bool {
        guard let selectedApp, !selectedApp.isDefault else {
            return false
        }

        return model.isApplicationPinned(bundleIdentifier: selectedApp.bundleIdentifier)
    }

    private var selectedScopeEffectiveProfileID: UUID? {
        guard let selectedApp else {
            return nil
        }

        return model.profileIDForApplication(
            bundleIdentifier: selectedApp.isDefault ? nil : selectedApp.bundleIdentifier,
            controllerIdentifier: model.selectedControllerIdentifier
        )
    }

    private var selectedScopeEffectiveProfileName: String? {
        guard let selectedScopeEffectiveProfileID else {
            return nil
        }

        return model.profileName(for: selectedScopeEffectiveProfileID)
    }

    private var selectedApplicationOutputEnabled: Bool {
        if selectedApp?.isDefault == true {
            return model.defaultApplicationOutputEnabled
        }

        guard let selectedAppRule else {
            return model.defaultApplicationOutputEnabled
        }

        if case .disableOutput = selectedAppRule.action {
            return false
        }

        return true
    }

    private var hasPendingMappingSave: Bool {
        pendingMappingSave != nil
    }

    private var selectedApplicationOutputBinding: Binding<Bool> {
        Binding(
            get: { selectedApplicationOutputEnabled },
            set: { isEnabled in
                guard let selectedApp else { return }
                if selectedApp.isDefault {
                    model.defaultApplicationOutputEnabled = isEnabled
                } else if isEnabled {
                    model.assignAppToSelectedProfile(
                        bundleIdentifier: selectedApp.bundleIdentifier,
                        appName: selectedApp.appName,
                        controllerIdentifier: model.selectedControllerIdentifier
                    )
                } else {
                    model.disableOutputForApp(
                        bundleIdentifier: selectedApp.bundleIdentifier,
                        appName: selectedApp.appName,
                        controllerIdentifier: model.selectedControllerIdentifier
                    )
                }
            }
        )
    }

    private func selectProfile(_ profileID: UUID) {
        clearPendingMappingChanges()
        model.selectedProfileID = profileID
        assignProfile(profileID, to: currentProfileAssignmentTarget)
    }

    private var isDefaultProfileSelected: Bool {
        model.selectedProfileID == model.profiles.first?.id
    }

    private var defaultProfileHasCustomMappings: Bool {
        guard let defaultProfile = model.profiles.first else {
            return false
        }

        return Paddle.allCases.contains { paddle in
            guard let defaultAction = MappingProfile.defaultActions[paddle] else {
                return false
            }

            return defaultProfile.action(for: paddle) != defaultAction
        }
    }

    private func syncProfileForSelectedApplication() {
        guard let selectedApp else {
            return
        }

        model.syncSelectedProfileForApplication(
            bundleIdentifier: selectedApp.isDefault ? nil : selectedApp.bundleIdentifier,
            controllerIdentifier: model.selectedControllerIdentifier
        )
    }

    private func saveMappingChanges() {
        guard let pendingMappingSave else {
            clearPendingMappingChanges()
            return
        }

        assignProfile(pendingMappingSave.profileID, to: pendingMappingSave.target)
        clearPendingMappingChanges()
    }

    private func clearPendingMappingChanges() {
        pendingMappingSave = nil
        pendingChangedPaddles.removeAll()
    }

    private var currentProfileAssignmentTarget: ProfileAssignmentTarget? {
        guard selectedApplicationOutputEnabled, let selectedApp else {
            return nil
        }

        if selectedApp.isDefault {
            return .defaultApplication(controllerIdentifier: model.selectedControllerIdentifier)
        }

        return .application(
            bundleIdentifier: selectedApp.bundleIdentifier,
            appName: selectedApp.appName,
            controllerIdentifier: model.selectedControllerIdentifier
        )
    }

    private func assignProfile(_ profileID: UUID, to target: ProfileAssignmentTarget?) {
        guard let target else {
            return
        }

        switch target {
        case .defaultApplication(let controllerIdentifier):
            model.useProfileForDefaultApplication(profileID: profileID, controllerIdentifier: controllerIdentifier)
        case .application(let bundleIdentifier, let appName, let controllerIdentifier):
            model.assignApp(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                controllerIdentifier: controllerIdentifier,
                toProfileID: profileID
            )
        }
    }

    private func selectController(identifier: String?) {
        model.selectController(identifier: identifier)
        syncProfileForSelectedApplication()
    }

    private func toggleSelectedControllerPin() {
        guard let controller = model.selectedControllerSelection else {
            return
        }

        if model.selectedControllerIsPinned {
            model.unpinSelectedController()
            syncProfileForSelectedApplication()
            return
        }

        guard model.selectedControllerHasCustomDisplayName else {
            promptToNameAndPinController(controller)
            return
        }

        model.pinSelectedController()
    }

    private func promptToNameAndPinController(_ controller: MenuBarControllerSelection) {
        let alert = NSAlert()
        alert.messageText = "Name controller before pinning"
        alert.informativeText = "Pinned controllers stay in the controller list when disconnected. Give this controller a unique name first."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Pin")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = controller.productName
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let trimmedName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            NSSound.beep()
            return
        }

        model.pinSelectedController(displayName: trimmedName)
    }

    private func resetDefaultProfileMappings() {
        guard isDefaultProfileSelected else {
            return
        }

        model.resetSelectedProfileToDefaults(markAsPendingChange: false)
        clearPendingMappingChanges()
    }

    private func confirmDeleteSelectedProfile() {
        guard model.canDeleteSelectedProfile else {
            return
        }

        let profileName = model.selectedProfileName
        let alert = NSAlert()
        alert.messageText = "Delete \(profileName)?"
        alert.informativeText = "This removes the profile and any application rules using it. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteSelectedProfile()
            clearPendingMappingChanges()
        }
    }

    private func selectDefaultAppIfNeeded() {
        guard selectedAppBundleIdentifier == nil || !appSelections.contains(where: { $0.bundleIdentifier == selectedAppBundleIdentifier }) else {
            return
        }

        selectedAppBundleIdentifier = appSelections.first?.bundleIdentifier
    }

    private func toggleSelectedApplicationPin() {
        guard let selectedApp, !selectedApp.isDefault else {
            return
        }

        if selectedApplicationIsPinned {
            model.unpinApplication(bundleIdentifier: selectedApp.bundleIdentifier, appName: selectedApp.appName)
        } else {
            model.pinApplication(bundleIdentifier: selectedApp.bundleIdentifier, appName: selectedApp.appName)
        }
    }

    private func addApplicationRule() {
        let panel = NSOpenPanel()
        panel.title = "Add App"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        panel.begin { response in
            guard response == .OK, let appURL = panel.url else {
                return
            }

            guard let bundle = Bundle(url: appURL), let bundleIdentifier = bundle.bundleIdentifier else {
                NSSound.beep()
                return
            }

            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                appURL.deletingPathExtension().lastPathComponent

            model.pinApplication(bundleIdentifier: bundleIdentifier, appName: displayName)
            selectedAppBundleIdentifier = bundleIdentifier
        }
    }

    private func beginCreatingProfile() {
        draftProfileName = ""
        isCreatingProfile = true
        isRenamingProfile = false
    }

    private func beginRenamingController() {
        guard let controller = model.selectedControllerSelection else {
            return
        }

        draftControllerName = controller.displayName
        isRenamingController = true
    }

    private func saveControllerNameEdit() {
        model.renameSelectedController(to: draftControllerName)
        cancelControllerNameEdit()
    }

    private func cancelControllerNameEdit() {
        draftControllerName = ""
        isRenamingController = false
    }

    private func beginRenamingProfile() {
        draftProfileName = model.selectedProfileName
        isRenamingProfile = true
        isCreatingProfile = false
    }

    private func saveProfileNameEdit() {
        if isCreatingProfile {
            model.createProfile()
            clearPendingMappingChanges()
            model.renameSelectedProfile(to: draftProfileName)
            assignProfile(model.selectedProfileID, to: currentProfileAssignmentTarget)
        } else if isRenamingProfile {
            model.renameSelectedProfile(to: draftProfileName)
        }

        cancelProfileNameEdit()
    }

    private func cancelProfileNameEdit() {
        draftProfileName = ""
        isCreatingProfile = false
        isRenamingProfile = false
    }

    private var controllerStatusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controllerStatusColor)
                .frame(width: 9, height: 9)
            Text(controllerStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !model.paddleDeviceStatus.isConnected {
                Button {
                    model.refreshPaddleMonitor()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Retry Controller Detection")
            }
        }
    }

    private var controllerStatusColor: Color {
        if !model.inputMonitoringTrusted {
            return .red
        }

        if model.paddleDeviceStatus.isConnected {
            return .green
        }

        if model.paddleDeviceStatus.unsupportedControllerCount > 0 {
            return .orange
        }

        return .red
    }

    private var controllerStatusText: String {
        if !model.inputMonitoringTrusted {
            return "Controller Input Access: Permission Needed"
        }

        if model.paddleDeviceStatus.isConnected {
            let deviceName = model.paddleDeviceStatus.deviceName ?? "Unknown Device"
            if model.paddleDeviceStatus.connectedDeviceCount > 1 {
                return "Connected: \(model.paddleDeviceStatus.connectedDeviceCount) controllers"
            }
            return "Connected: \(deviceName)"
        }

        if model.paddleDeviceStatus.unsupportedControllerCount > 0 {
            let knownEliteCount = model.paddleDeviceStatus.unsupportedControllers.filter(\.isKnownXboxEliteSeries2).count
            if knownEliteCount > 0 {
                if knownEliteCount > 1 {
                    return "Disconnected: Elite 2 controllers detected, unsupported connection"
                }

                let deviceName = model.paddleDeviceStatus.unsupportedControllers.first(where: \.isKnownXboxEliteSeries2)?.productName ?? "Elite 2 Controller"
                return "Disconnected: \(deviceName) detected, unsupported connection"
            }

            if model.paddleDeviceStatus.unsupportedControllerCount > 1 {
                return "Disconnected: Controllers detected, no Elite 2 paddle input"
            }

            let deviceName = model.paddleDeviceStatus.unsupportedControllerName ?? "Controller"
            return "Disconnected: \(deviceName) detected, no Elite 2 paddle input"
        }

        return "Disconnected: No Xbox Elite Device Found"
    }

    private var outputDescription: String {
        if !model.outputEnabled || !model.effectiveOutputEnabled {
            return "Paddle mappings are disabled"
        }

        return "Paddle mappings are enabled"
    }

    private var accessibilityStatusRow: some View {
        PermissionStatusRowView(
            isTrusted: model.accessibilityTrusted,
            trustedText: "Accessibility: Trusted",
            neededText: "Accessibility: Permission Needed",
            buttonTitle: "Grant Accessibility Permission",
            systemImage: "hand.raised.fill",
            helpText: "Open the macOS Accessibility permission prompt for Paddlr keyboard output",
            detailText: "Required for paddle keyboard output.",
            action: {
                model.refreshAccessibilityTrust(prompt: true)
            }
        )
    }

    private var controllerInputAccessStatusRow: some View {
        let isRequestEnabled = model.accessibilityTrusted
        return PermissionStatusRowView(
            isTrusted: model.inputMonitoringTrusted,
            trustedText: "Controller Input Access: Ready",
            neededText: "Controller Input Access: Permission Needed",
            buttonTitle: "Grant Controller Input Access",
            systemImage: "keyboard",
            helpText: isRequestEnabled
                ? "Open the macOS permission prompt for raw controller input"
                : "Grant Accessibility first; Paddlr will enable this button if controller input access is still needed",
            detailText: isRequestEnabled
                ? "Required before Paddlr starts controller detection."
                : "Grant Accessibility first. This button becomes available only if controller input access is still needed afterward.",
            isButtonEnabled: isRequestEnabled,
            action: {
                model.refreshInputMonitoringTrust(prompt: true)
            }
        )
    }

    private var mappingsSection: some View {
        MappingsSectionView(
            model: model,
            hasPendingMappingSave: hasPendingMappingSave,
            showsDiagnosticHelperText: showsDiagnosticHelperText,
            selectedProfileName: model.selectedProfileName,
            pendingChangedPaddles: pendingChangedPaddles,
            onSave: saveMappingChanges
        )
    }

    private var eventLogSection: some View {
        RecentEventsSectionView(isExpanded: $isRecentEventsExpanded, events: model.recentEvents)
    }

    private var footer: some View {
        HStack {
            if showsDiagnosticHelperText {
                Text("Keyboard output only; Xbox button output is deferred")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
