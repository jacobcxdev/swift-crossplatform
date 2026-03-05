// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

/// All Showcase playgrounds, matching upstream skipapp-showcase-fuse exactly (84 cases).
enum PlaygroundType: String, CaseIterable, Identifiable, Equatable, Hashable {
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

    var id: String { rawValue }

    /// Display title matching upstream skipapp-showcase-fuse titles exactly.
    var title: String {
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

    /// SF Symbol name for the playground list icon.
    var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .alert: "exclamationmark.triangle"
        case .animation: "wind"
        case .background: "rectangle.inset.filled"
        case .blendMode: "circle.lefthalf.filled"
        case .blur: "aqi.medium"
        case .border: "rectangle"
        case .button: "rectangle.and.hand.point.up.left"
        case .color: "paintpalette"
        case .colorEffects: "wand.and.stars"
        case .colorScheme: "circle.lefthalf.filled"
        case .compose: "gear"
        case .confirmationDialog: "questionmark.diamond"
        case .datePicker: "calendar"
        case .disclosureGroup: "chevron.down.circle"
        case .divider: "minus"
        case .documentPicker: "doc"
        case .environment: "leaf"
        case .focusState: "scope"
        case .form: "doc.plaintext"
        case .frame: "aspectratio"
        case .gesture: "hand.tap"
        case .geometryReader: "ruler"
        case .gradient: "paintbrush"
        case .graphics: "scribble"
        case .grid: "square.grid.3x3"
        case .hapticFeedback: "waveform"
        case .icon: "star"
        case .image: "photo"
        case .keyboard: "keyboard"
        case .keychain: "key"
        case .label: "tag"
        case .lineSpacing: "text.alignleft"
        case .link: "link"
        case .list: "list.bullet"
        case .localization: "globe"
        case .lottie: "play.circle"
        case .map: "map"
        case .mask: "theatermasks"
        case .minimumScaleFactor: "textformat.size"
        case .menu: "ellipsis.circle"
        case .modifier: "slider.horizontal.3"
        case .navigationStack: "square.stack.3d.up"
        case .notification: "bell"
        case .observable: "eye"
        case .offsetPosition: "arrow.up.and.down.and.arrow.left.and.right"
        case .onSubmit: "return"
        case .overlay: "square.on.square"
        case .pasteboard: "doc.on.clipboard"
        case .picker: "filemenu.and.selection"
        case .preference: "gearshape"
        case .progressView: "clock"
        case .redacted: "rectangle.badge.minus"
        case .safeArea: "rectangle.dashed"
        case .scenePhase: "moon"
        case .scrollView: "scroll"
        case .searchable: "magnifyingglass"
        case .secureField: "lock"
        case .shadow: "shadow"
        case .shape: "diamond"
        case .shareLink: "square.and.arrow.up"
        case .sheet: "rectangle.bottomthird.inset.filled"
        case .slider: "slider.horizontal.below.rectangle"
        case .spacer: "arrow.left.and.right"
        case .sql: "cylinder"
        case .stack: "square.stack"
        case .state: "memorychip"
        case .stepper: "plus.forwardslash.minus"
        case .storage: "externaldrive"
        case .symbol: "character.textbox"
        case .tabView: "rectangle.split.3x1"
        case .text: "textformat"
        case .textEditor: "doc.text"
        case .textField: "character.cursor.ibeam"
        case .timer: "timer"
        case .toggle: "switch.2"
        case .toolbar: "menubar.rectangle"
        case .tracking: "location"
        case .transform: "arrow.triangle.2.circlepath"
        case .transition: "rectangle.2.swap"
        case .videoPlayer: "play.rectangle"
        case .viewThatFits: "rectangle.compress.vertical"
        case .webView: "safari"
        case .zIndex: "square.3.layers.3d.down.right"
        }
    }
}
