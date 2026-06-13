import AppKit
import PaddlrCore
import SwiftUI

struct ControllerSectionView: View {
    let controllers: [MenuBarControllerSelection]
    let selectedIdentifier: String?
    let selectedControllerExists: Bool
    let canPinSelectedController: Bool
    let isSelectedControllerPinned: Bool
    let isRenaming: Bool
    @Binding var draftName: String
    let onSelect: (String?) -> Void
    let onBeginRename: () -> Void
    let onTogglePin: () -> Void
    let onSaveRename: () -> Void
    let onCancelRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Controller")
                .font(.headline)

            if isRenaming {
                TextField("Controller name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save", action: onSaveRename)
                    Button("Cancel", action: onCancelRename)
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    ControllerPickerButton(
                        controllers: controllers,
                        selectedIdentifier: selectedIdentifier,
                        onSelect: onSelect
                    )
                    .frame(width: MappingPanelView.selectorWidth, height: 24, alignment: .leading)
                    .disabled(controllers.isEmpty)

                    Button(action: onBeginRename) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!selectedControllerExists)
                    .help("Rename Controller")

                    if canPinSelectedController {
                        Button(action: onTogglePin) {
                            Image(systemName: isSelectedControllerPinned ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.borderless)
                        .help(isSelectedControllerPinned ? "Unpin Controller" : "Pin Controller")
                    }
                }
            }
        }
    }
}

struct ApplicationSectionView: View {
    let apps: [AppSelection]
    let selectedBundleIdentifier: String?
    let selectedApplicationIsPinned: Bool
    let selectedApplicationIsDefault: Bool
    let outputEnabled: Binding<Bool>
    let onSelect: (String?) -> Void
    let onAdd: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Application")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                AppPickerButton(
                    apps: apps,
                    selectedBundleIdentifier: selectedBundleIdentifier,
                    onSelect: onSelect
                )
                .frame(width: MappingPanelView.selectorWidth, height: 24, alignment: .leading)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add App")

                Button(action: onTogglePin) {
                    Image(systemName: selectedApplicationIsPinned ? "xmark" : "pin")
                }
                .buttonStyle(.borderless)
                .disabled(selectedApplicationIsDefault)
                .help(selectedApplicationIsPinned ? "Unpin App" : "Pin App")

                Spacer()

                Toggle("Enable for this app", isOn: outputEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .disabled(selectedBundleIdentifier == nil)
            }
        }
    }
}

struct ProfileSectionView: View {
    let profiles: [MappingProfile]
    let selectedProfileID: UUID
    let isDefaultProfileSelected: Bool
    let defaultProfileHasCustomMappings: Bool
    let isCreatingProfile: Bool
    let isRenamingProfile: Bool
    @Binding var draftProfileName: String
    let profileDetailText: String?
    let onSelectProfile: (UUID) -> Void
    let onBeginCreate: () -> Void
    let onResetDefault: () -> Void
    let onBeginRename: () -> Void
    let onConfirmDelete: () -> Void
    let onSaveNameEdit: () -> Void
    let onCancelNameEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.headline)

            if isCreatingProfile || isRenamingProfile {
                TextField("Profile name", text: $draftProfileName)
                    .textFieldStyle(.roundedBorder)
            } else {
                HStack(spacing: 8) {
                    ProfilePickerButton(
                        profiles: profiles,
                        selectedProfileID: selectedProfileID,
                        onSelect: onSelectProfile
                    )
                    .frame(width: MappingPanelView.selectorWidth, height: 24, alignment: .leading)

                    Button(action: onBeginCreate) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Profile")

                    if isDefaultProfileSelected {
                        if defaultProfileHasCustomMappings {
                            Button(action: onResetDefault) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Reset Default Profile")
                        }
                    } else {
                        Button(action: onBeginRename) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Rename Profile")

                        Button(action: onConfirmDelete) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Profile")
                    }
                }
            }

            if isCreatingProfile || isRenamingProfile {
                HStack {
                    Button("Save", action: onSaveNameEdit)
                    Button("Cancel", action: onCancelNameEdit)
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
}

struct MappingsSectionView: View {
    @ObservedObject var model: MenuBarMapperModel
    let hasPendingMappingSave: Bool
    let showsDiagnosticHelperText: Bool
    let selectedProfileName: String
    let pendingChangedPaddles: Set<Paddle>
    let onSave: () -> Void

    private static let paddleGridOrder: [Paddle] = [.three, .one, .four, .two]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mappings")
                    .font(.headline)
                Spacer()
                if hasPendingMappingSave {
                    Button("Save", action: onSave)
                        .buttonStyle(.bordered)
                } else if showsDiagnosticHelperText {
                    Text("Editing: \(selectedProfileName)")
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
}

struct RecentEventsSectionView: View {
    @Binding var isExpanded: Bool
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent events")
                    .font(.headline)
                Spacer()
                Button(isExpanded ? "Hide" : "Show") {
                    isExpanded.toggle()
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
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
}
