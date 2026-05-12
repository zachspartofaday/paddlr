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

private struct AppSelection: Identifiable, Hashable {
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

    private static let selectorWidth: CGFloat = 260
    private static let paddleGridOrder: [Paddle] = [.three, .one, .four, .two]

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Controller")
                .font(.headline)

            if isRenamingController {
                TextField("Controller name", text: $draftControllerName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        saveControllerNameEdit()
                    }
                    Button("Cancel") {
                        cancelControllerNameEdit()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    ControllerPickerButton(
                        controllers: model.connectedControllerSelections,
                        selectedIdentifier: model.selectedControllerIdentifier,
                        onSelect: selectController
                    )
                    .frame(width: Self.selectorWidth, height: 24, alignment: .leading)
                    .disabled(model.connectedControllerSelections.isEmpty)

                    Button {
                        beginRenamingController()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedControllerSelection == nil)
                    .help("Rename Controller")

                    if model.selectedControllerCanPin {
                        Button {
                            toggleSelectedControllerPin()
                        } label: {
                            Image(systemName: model.selectedControllerIsPinned ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.borderless)
                        .help(model.selectedControllerIsPinned ? "Unpin Controller" : "Pin Controller")
                    }
                }
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.headline)

            if isCreatingProfile || isRenamingProfile {
                TextField("Profile name", text: $draftProfileName)
                    .textFieldStyle(.roundedBorder)
            } else {
                HStack(spacing: 8) {
                    ProfilePickerButton(
                        profiles: model.profiles,
                        selectedProfileID: model.selectedProfileID,
                        onSelect: selectProfile
                    )
                    .frame(width: Self.selectorWidth, height: 24, alignment: .leading)

                    Button {
                        beginCreatingProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Profile")

                    if isDefaultProfileSelected {
                        if defaultProfileHasCustomMappings {
                            Button {
                                resetDefaultProfileMappings()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Reset Default Profile")
                        }
                    } else {
                        Button {
                            beginRenamingProfile()
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Rename Profile")

                        Button {
                            confirmDeleteSelectedProfile()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Profile")
                    }
                }
            }

            if isCreatingProfile || isRenamingProfile {
                HStack {
                    Button("Save") {
                        saveProfileNameEdit()
                    }
                    Button("Cancel") {
                        cancelProfileNameEdit()
                    }
                }
                .buttonStyle(.bordered)
            }

            if let profileDetailText {
                Text(profileDetailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Application")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                AppPickerButton(
                    apps: appSelections,
                    selectedBundleIdentifier: selectedApp?.bundleIdentifier,
                    onSelect: { selectedAppBundleIdentifier = $0 }
                )
                .frame(width: Self.selectorWidth, height: 24, alignment: .leading)

                Button {
                    addApplicationRule()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add App")

                Button {
                    toggleSelectedApplicationPin()
                } label: {
                    Image(systemName: selectedApplicationIsPinned ? "xmark" : "pin")
                }
                .buttonStyle(.borderless)
                .disabled(selectedApp?.isDefault ?? true)
                .help(selectedApplicationIsPinned ? "Unpin App" : "Pin App")

                Spacer()

                Toggle("Enable for this app", isOn: selectedApplicationOutputBinding)
                    .toggleStyle(SwitchToggleStyle())
                    .disabled(selectedApp == nil)
            }
        }
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
        permissionStatusRow(
            isTrusted: model.accessibilityTrusted,
            trustedText: "Accessibility: Trusted",
            neededText: "Accessibility: Permission Needed",
            buttonTitle: "Grant Accessibility Permission",
            systemImage: "hand.raised.fill",
            helpText: "Open the macOS Accessibility permission prompt for Paddlr keyboard output",
            detailText: "Required for paddle keyboard output."
        ) {
            model.refreshAccessibilityTrust(prompt: true)
        }
    }

    private var controllerInputAccessStatusRow: some View {
        let isRequestEnabled = model.accessibilityTrusted
        return permissionStatusRow(
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
            isButtonEnabled: isRequestEnabled
        ) {
            model.refreshInputMonitoringTrust(prompt: true)
        }
    }

    private func permissionStatusRow(
        isTrusted: Bool,
        trustedText: String,
        neededText: String,
        buttonTitle: String,
        systemImage: String,
        helpText: String,
        detailText: String,
        isButtonEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
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

    private var mappingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mappings")
                    .font(.headline)
                Spacer()
                if hasPendingMappingSave {
                    Button("Save") {
                        saveMappingChanges()
                    }
                    .buttonStyle(.bordered)
                } else if showsDiagnosticHelperText {
                    Text("Editing: \(model.selectedProfileName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(Self.paddleGridOrder, id: \.self) { paddle in
                    PaddleMappingRow(
                        model: model,
                        paddle: paddle,
                        isPendingChange: pendingChangedPaddles.contains(paddle)
                    )
                }
            }
        }
    }

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent events")
                    .font(.headline)
                Spacer()
                Button(isRecentEventsExpanded ? "Hide" : "Show") {
                    isRecentEventsExpanded.toggle()
                }
                .buttonStyle(.borderless)
            }

            if isRecentEventsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.recentEvents.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 132)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
        }
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

private struct PaddleMappingRow: View {
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

private struct ControllerPickerButton: NSViewRepresentable {
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

private struct ProfilePickerButton: NSViewRepresentable {
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

private struct AppPickerButton: NSViewRepresentable {
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

private struct BindingMenuButton: NSViewRepresentable {
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

private struct PaddleStateIndicator: View {
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
