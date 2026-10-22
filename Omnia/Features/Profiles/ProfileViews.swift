import SwiftUI

/// Nuvio's "Who's watching?": every profile on the account, a PIN for
/// locked ones, and Manage Profiles to add, edit or remove them.
struct ProfilePickerView: View {
    @Environment(ProfileStore.self) private var profiles
    @State private var isManaging = false
    @State private var editing: EditorTarget?
    @State private var unlocking: ViewerProfile?
    var title = "Who's Watching?"
    var onChosen: (ViewerProfile) -> Void = { _ in }
    /// Shown when the page was opened with Switch Profile, to go back.
    var onCancel: (() -> Void)?
    /// Where each avatar sits, so the switch animation starts from it.
    @State private var avatarCenters: [UUID: CGPoint] = [:]
    @State private var appeared = false
    @State private var pointer = UnitPoint(x: 0.5, y: 0.35)
    @State private var size = CGSize.zero

    var body: some View {
        ZStack {
            AccentSpotlightBackground(pointer: pointer)
            VStack(spacing: 36) {
                OmniaWordmark(height: 40)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)
                Text(isManaging ? "Manage Profiles" : title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.opacity)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                profileRow
                Button(isManaging ? "Done" : "Manage Profiles") {
                    withAnimation(.smooth) { isManaging.toggle() }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .opacity(appeared ? 1 : 0)
            }
            .padding(40)
        }
        .overlay(alignment: .topLeading) {
            if let onCancel {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
                .padding(20)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onContinuousHover { phase in
            guard case let .active(location) = phase, size.width > 0, size.height > 0 else { return }
            withAnimation(.smooth(duration: 1.4)) {
                pointer = UnitPoint(x: location.x / size.width, y: location.y / size.height)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { appeared = true }
        }
        .sheet(item: $editing) { target in
            ProfileEditorView(target: target)
        }
        .sheet(item: $unlocking) { profile in
            PINEntrySheet(profile: profile) { pin in
                let result = profiles.select(profile.id, pin: pin)
                if result == .accepted {
                    unlocking = nil
                    choose(profile)
                }
                return result
            }
        }
    }

    /// Plays the switch animation from the tapped avatar, then hands over.
    private func choose(_ profile: ViewerProfile) {
        ProfileSwitchCenter.shared.beginSwitch(to: profile, from: avatarCenters[profile.id])
        onChosen(profile)
    }

    /// Centred when every tile fits; scrolls only in a narrow window.
    private var profileRow: some View {
        ViewThatFits(in: .horizontal) {
            tiles
            ScrollView(.horizontal) { tiles }
                .scrollIndicators(.never)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tiles: some View {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        if isManaging {
                            editing = .edit(profile)
                        } else if profile.isLocked, profile.id != profiles.activeProfileID || profiles.needsSelection {
                            unlocking = profile
                        } else {
                            profiles.select(profile.id)
                            choose(profile)
                        }
                    } label: {
                        ProfileTile(profile: profile, isManaging: isManaging)
                            .onGeometryChange(for: CGPoint.self) { proxy in
                                let frame = proxy.frame(in: .global)
                                return CGPoint(x: frame.midX, y: frame.minY + ProfileTile.avatarSize / 2)
                            } action: { center in
                                avatarCenters[profile.id] = center
                            }
                    }
                    .buttonStyle(ProfileTileButtonStyle())
                    // Nuvio's tiles rise in one after another.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 28)
                    .animation(.spring(response: 0.8, dampingFraction: 0.82).delay(0.1 * Double(index) + 0.15), value: appeared)
                    .accessibilityLabel(profile.name)
                    .accessibilityHint(isManaging ? "Edit profile" : profile.isLocked ? "Locked with a PIN" : "Watch as \(profile.name)")
                }
                if profiles.canAddProfile {
                    Button { editing = .new } label: {
                        VStack(spacing: 12) {
                            Circle()
                                .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .frame(width: 120, height: 120)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            Text("Add Profile")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 132)
                    }
                    .buttonStyle(ProfileTileButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }
}

enum EditorTarget: Identifiable, Hashable {
    case new
    case edit(ViewerProfile)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(profile): profile.id.uuidString
        }
    }
}

private struct ProfileTile: View {
    static let avatarSize: CGFloat = 120
    let profile: ViewerProfile
    let isManaging: Bool

    var body: some View {
        VStack(spacing: 12) {
            ProfileAvatarView(profile: profile, size: Self.avatarSize)
                .overlay {
                    if isManaging {
                        Circle()
                            .fill(.black.opacity(0.45))
                        Image(systemName: "pencil")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            HStack(spacing: 5) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                if profile.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 130)
        }
        // Every tile the same width, so the row's spacing is even.
        .frame(width: 132)
    }
}

/// Grows a little on hover and shrinks when pressed, like Nuvio's tiles.
struct ProfileTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverScaledLabel(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct HoverScaledLabel<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @State private var isHovering = false

        var body: some View {
            label
                .scaleEffect(isPressed ? 0.95 : isHovering ? 1.06 : 1)
                .animation(.spring(duration: 0.25), value: isHovering)
                .animation(.spring(duration: 0.2), value: isPressed)
                .onHover { isHovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Editor

/// Name, avatar, colour and PIN for one profile.
struct ProfileEditorView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget
    @State private var name: String
    @State private var avatarID: String?
    @State private var colorHex: String
    @State private var pinMode: PINMode = .unchanged
    @State private var newPIN = ""
    @State private var confirmsDelete = false
    @State private var usesMainSettings = false
    @State private var usesMainAddons = false
    @State private var usesMainPlugins = false

    private enum PINMode: Equatable { case unchanged, setting, removing }

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _avatarID = State(initialValue: AvatarCatalog.random().id)
            _colorHex = State(initialValue: ViewerProfile.colors.randomElement() ?? "705CFF")
        case let .edit(profile):
            _name = State(initialValue: profile.name)
            _avatarID = State(initialValue: profile.avatarID)
            _colorHex = State(initialValue: profile.colorHex)
            _usesMainSettings = State(initialValue: profile.usesMainSettings)
            _usesMainAddons = State(initialValue: profile.usesMainAddons)
            _usesMainPlugins = State(initialValue: profile.usesMainPlugins)
        }
    }

    private var existing: ViewerProfile? {
        guard case let .edit(profile) = target else { return nil }
        return profiles.profiles.first { $0.id == profile.id }
    }

    private var canSave: Bool {
        !ViewerProfile.cleanName(name).isEmpty && (pinMode != .setting || ProfileStore.isValidPIN(newPIN))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    colorRow
                    if !isMain {
                        sharingSection
                    }
                    pinSection
                    avatarGrid
                    if let existing, !isMain {
                        Button("Delete Profile", role: .destructive) { confirmsDelete = true }
                            .confirmationDialog(
                                "Delete \(existing.name)?",
                                isPresented: $confirmsDelete,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    profiles.delete(existing.id)
                                    dismiss()
                                }
                            } message: {
                                Text("Their library, progress and settings are removed from this Mac and your account.")
                            }
                    }
                }
                .padding(24)
            }
            .navigationTitle(existing == nil ? "New Profile" : "Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 640, idealHeight: 720)
    }

    private var header: some View {
        HStack(spacing: 20) {
            ProfileAvatarView(name: name.isEmpty ? "?" : name, avatarID: avatarID, colorHex: colorHex, size: 112)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onChange(of: name) { _, value in
                        if value.count > ViewerProfile.maximumNameLength {
                            name = String(value.prefix(ViewerProfile.maximumNameLength))
                        }
                    }
                HStack(spacing: 10) {
                    if isMain {
                        Label("Main Profile", systemImage: "crown.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Button("Use Initial Instead", systemImage: "textformat") {
                        avatarID = nil
                    }
                    .buttonStyle(.glass)
                    .disabled(avatarID == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").font(.headline)
            HStack(spacing: 8) {
                ForEach(ViewerProfile.colors, id: \.self) { hex in
                    Button { colorHex = hex } label: {
                        Circle()
                            .fill(Color(profileHex: hex))
                            .frame(width: 26, height: 26)
                            .overlay {
                                if hex == colorHex {
                                    Circle().strokeBorder(.primary, lineWidth: 2.5).padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(hex)")
                    .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatarGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Avatar").font(.title3.weight(.semibold))
            AvatarPicker(selection: $avatarID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The main profile is the first one; it can't be deleted or share.
    private var isMain: Bool {
        guard let existing else { return profiles.profiles.isEmpty }
        return existing.id == profiles.mainProfileID
    }

    /// Nuvio's "use the primary profile's add-ons and plugins", with
    /// settings too, as Omnia keeps those per profile.
    /// One switch for all three, like Nuvio.
    private var usesMainProfile: Binding<Bool> {
        Binding {
            usesMainSettings || usesMainAddons || usesMainPlugins
        } set: { uses in
            usesMainSettings = uses
            usesMainAddons = uses
            usesMainPlugins = uses
        }
    }

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Use Main Profile Settings").font(.headline)
                Spacer()
                Toggle("Use Main Profile Settings", isOn: usesMainProfile)
                    .labelsHidden()
            }
            Text("Shares the main profile's settings, Home layout, collections, add-ons and plugins. Library and progress stay this profile's own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile Lock").font(.headline)
            switch pinMode {
            case .unchanged:
                HStack {
                    if existing?.isLocked == true {
                        Label("Locked with a PIN", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change PIN") { pinMode = .setting }
                        Button("Remove PIN") { pinMode = .removing }
                    } else {
                        Label("Anyone can open this profile", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Add a PIN") { pinMode = .setting }
                    }
                }
            case .setting:
                HStack {
                    SecureField("Four-digit PIN", text: $newPIN)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onChange(of: newPIN) { _, value in
                            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                            if digits != value { newPIN = digits }
                        }
                    Text("Asked for when switching to this profile. It stays on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        pinMode = .unchanged
                        newPIN = ""
                    }
                }
            case .removing:
                HStack {
                    Label("The PIN will be removed when you save.", systemImage: "lock.open")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Keep PIN") { pinMode = .unchanged }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        let profileID: UUID
        if var profile = existing {
            profile.name = name
            profile.avatarID = avatarID
            profile.colorHex = colorHex
            if !isMain {
                profile.usesMainSettings = usesMainSettings
                profile.usesMainAddons = usesMainAddons
                profile.usesMainPlugins = usesMainPlugins
            }
            profiles.update(profile)
            profileID = profile.id
        } else if var created = profiles.create(name: name, avatarID: avatarID, colorHex: colorHex) {
            if created.id != profiles.mainProfileID {
                created.usesMainSettings = usesMainSettings
                created.usesMainAddons = usesMainAddons
                created.usesMainPlugins = usesMainPlugins
                profiles.update(created)
            }
            profileID = created.id
        } else {
            dismiss()
            return
        }
        switch pinMode {
        case .setting: profiles.setPIN(newPIN, for: profileID)
        case .removing: profiles.setPIN(nil, for: profileID)
        case .unchanged: break
        }
        dismiss()
    }
}

// MARK: - PIN

struct PINEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: ViewerProfile
    let submit: (String) -> ProfileStore.PINResult
    @State private var pin = ""
    @State private var message: String?
    @State private var shakes = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            ProfileAvatarView(profile: profile, size: 84)
            Text("Enter \(profile.name)'s PIN")
                .font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? AnyShapeStyle(OmniaBrandColors.gradient) : AnyShapeStyle(.quaternary))
                        .frame(width: 16, height: 16)
                }
            }
            .modifier(ShakeEffect(shakes: CGFloat(shakes)))
            .animation(.default, value: shakes)
            // The field is invisible; the dots show what's typed.
            SecureField("PIN", text: $pin)
                .focused($isFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: pin) { _, value in
                    let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4))
                    if digits != value {
                        pin = digits
                        return
                    }
                    if digits.count == 4 { check(digits) }
                }
                .accessibilityLabel("Four-digit PIN")
            Text(message ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 360)
        .onAppear { isFocused = true }
        .onTapGesture { isFocused = true }
    }

    private func check(_ value: String) {
        switch submit(value) {
        case .accepted:
            message = nil
        case .wrong:
            message = "That PIN isn't right."
            shakes += 1
            pin = ""
        case let .lockedOut(until):
            let seconds = max(Int(until.timeIntervalSinceNow.rounded(.up)), 1)
            message = "Too many tries. Try again in \(seconds) seconds."
            shakes += 1
            pin = ""
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}
