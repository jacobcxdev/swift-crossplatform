// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

/// All Showcase playgrounds, matching upstream skipapp-showcase-fuse exactly (84 cases).
public enum PlaygroundType: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case accessibility
    case alert
    case animation
    case background
    case blendMode
    case blur
    case border
    case button
    case color
    case colorEffects
    case colorScheme
    case compose
    case confirmationDialog
    case datePicker
    case disclosureGroup
    case divider
    case documentPicker
    case environment
    case focusState
    case form
    case frame
    case gesture
    case geometryReader
    case gradient
    case graphics
    case grid
    case hapticFeedback
    case icon
    case image
    case keyboard
    case keychain
    case label
    case lineSpacing
    case link
    case list
    case localization
    case lottie
    case map
    case mask
    case minimumScaleFactor
    case menu
    case modifier
    case navigationStack
    case notification
    case observable
    case offsetPosition
    case onSubmit
    case overlay
    case pasteboard
    case picker
    case preference
    case progressView
    case redacted
    case safeArea
    case scenePhase
    case scrollView
    case searchable
    case secureField
    case shadow
    case shape
    case shareLink
    case sheet
    case slider
    case spacer
    case sql
    case stack
    case state
    case stepper
    case storage
    case symbol
    case tabView
    case text
    case textEditor
    case textField
    case timer
    case toggle
    case toolbar
    case tracking
    case transform
    case transition
    case videoPlayer
    case viewThatFits
    case webView
    case zIndex

    public var id: String { rawValue }

    /// Display title matching upstream skipapp-showcase-fuse titles exactly.
    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .alert: "Alert"
        case .animation: "Animation"
        case .background: "Background"
        case .blendMode: "BlendMode"
        case .blur: "Blur"
        case .border: "Border"
        case .button: "Button"
        case .color: "Color"
        case .colorEffects: "Color Effects"
        case .colorScheme: "ColorScheme"
        case .compose: "Compose"
        case .confirmationDialog: "ConfirmationDialog"
        case .datePicker: "DatePicker"
        case .disclosureGroup: "DisclosureGroup"
        case .divider: "Divider"
        case .documentPicker: "Document and Media Pickers"
        case .environment: "Environment"
        case .focusState: "FocusState"
        case .form: "Form"
        case .frame: "Frame"
        case .gesture: "Gesture"
        case .geometryReader: "GeometryReader"
        case .gradient: "Gradient"
        case .graphics: "Graphics"
        case .grid: "Grids"
        case .hapticFeedback: "Haptick Feedback"
        case .icon: "Icons"
        case .image: "Image"
        case .keyboard: "Keyboard"
        case .keychain: "Keychain"
        case .label: "Label"
        case .lineSpacing: "Line Spacing"
        case .link: "Link"
        case .list: "List"
        case .localization: "Localization"
        case .lottie: "Lottie Animation"
        case .map: "Map"
        case .mask: "Mask"
        case .minimumScaleFactor: "MinimumScaleFactor"
        case .menu: "Menu"
        case .modifier: "Modifiers"
        case .navigationStack: "NavigationStack"
        case .notification: "Notifications"
        case .observable: "Observable"
        case .offsetPosition: "Offset/Position"
        case .onSubmit: "OnSubmit"
        case .overlay: "Overlay"
        case .pasteboard: "Pasteboard"
        case .picker: "Picker"
        case .preference: "Preferences"
        case .progressView: "ProgressView"
        case .redacted: "Redacted"
        case .safeArea: "SafeArea"
        case .scenePhase: "ScenePhase"
        case .scrollView: "ScrollView"
        case .searchable: "Searchable"
        case .secureField: "SecureField"
        case .shadow: "Shadow"
        case .shape: "Shape"
        case .shareLink: "ShareLink"
        case .sheet: "Sheet"
        case .slider: "Slider"
        case .spacer: "Spacer"
        case .sql: "SQL"
        case .stack: "Stacks"
        case .state: "State"
        case .stepper: "Stepper"
        case .storage: "Storage"
        case .symbol: "Symbol"
        case .tabView: "TabView"
        case .text: "Text"
        case .textEditor: "TextEditor"
        case .textField: "TextField"
        case .timer: "Timer"
        case .toggle: "Toggle"
        case .toolbar: "Toolbar"
        case .tracking: "Tracking"
        case .transform: "Transform"
        case .transition: "Transition"
        case .videoPlayer: "Video Player"
        case .viewThatFits: "ViewThatFits"
        case .webView: "WebView"
        case .zIndex: "ZIndex"
        }
    }
}
