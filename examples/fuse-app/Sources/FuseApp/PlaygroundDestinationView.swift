// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import AlertFeature
import ComposableArchitecture
import SQLFeature
import SwiftUI
import ToggleFeature

/// Routes a `PlaygroundType` to its concrete playground view.
struct PlaygroundDestinationView: View {
    let type: PlaygroundType

    var body: some View {
        switch type {
        case .accessibility:
            AccessibilityPlayground()
        case .alert:
            AlertView(store: Store(initialState: AlertFeature.State()) { AlertFeature() })
        case .animation:
            AnimationPlayground()
        case .background:
            BackgroundPlayground()
        case .blendMode:
            BlendModePlayground()
        case .blur:
            BlurPlayground()
        case .border:
            BorderPlayground()
        case .button:
            ButtonPlayground()
        case .color:
            ColorPlayground()
        case .colorEffects:
            ColorEffectsPlayground()
        case .colorScheme:
            ColorSchemePlayground()
        case .compose:
            ComposePlayground()
        case .confirmationDialog:
            ConfirmationDialogPlayground()
        case .datePicker:
            DatePickerPlayground()
        case .disclosureGroup:
            DisclosureGroupPlayground()
        case .divider:
            DividerPlayground()
        case .documentPicker:
            DocumentPickerPlayground()
        case .environment:
            EnvironmentPlayground()
        case .focusState:
            FocusStatePlayground()
        case .form:
            FormPlayground()
        case .frame:
            FramePlayground()
        case .gesture:
            GesturePlayground()
        case .geometryReader:
            GeometryReaderPlayground()
        case .gradient:
            GradientPlayground()
        case .graphics:
            GraphicsPlayground()
        case .grid:
            GridPlayground()
        case .hapticFeedback:
            HapticFeedbackPlayground()
        case .icon:
            IconPlayground()
        case .image:
            ImagePlayground()
        case .keyboard:
            KeyboardPlayground()
        case .keychain:
            KeychainPlayground()
        case .label:
            LabelPlayground()
        case .lineSpacing:
            LineSpacingPlayground()
        case .link:
            LinkPlayground()
        case .list:
            ListPlayground()
        case .localization:
            LocalizationPlayground()
        case .lottie:
            LottiePlayground()
        case .map:
            MapPlayground()
        case .mask:
            MaskPlayground()
        case .minimumScaleFactor:
            MinimumScaleFactorPlayground()
        case .menu:
            MenuPlayground()
        case .modifier:
            ModifierPlayground()
        case .navigationStack:
            NavigationStackPlayground()
        case .notification:
            NotificationPlayground()
        case .observable:
            ObservablePlayground()
        case .offsetPosition:
            OffsetPositionPlayground()
        case .onSubmit:
            OnSubmitPlayground()
        case .overlay:
            OverlayPlayground()
        case .pasteboard:
            PasteboardPlayground()
        case .picker:
            PickerPlayground()
        case .preference:
            PreferencePlayground()
        case .progressView:
            ProgressViewPlayground()
        case .redacted:
            RedactedPlayground()
        case .safeArea:
            SafeAreaPlayground()
        case .scenePhase:
            ScenePhasePlayground()
        case .scrollView:
            ScrollViewPlayground()
        case .searchable:
            SearchablePlayground()
        case .secureField:
            SecureFieldPlayground()
        case .shadow:
            ShadowPlayground()
        case .shape:
            ShapePlayground()
        case .shareLink:
            ShareLinkPlayground()
        case .sheet:
            SheetPlayground()
        case .slider:
            SliderPlayground()
        case .spacer:
            SpacerPlayground()
        case .sql:
            SQLFeaturePlaygroundView()
        case .stack:
            StackPlayground()
        case .state:
            StatePlayground()
        case .stepper:
            StepperPlayground()
        case .storage:
            StoragePlayground()
        case .symbol:
            SymbolPlayground()
        case .tabView:
            TabViewPlayground()
        case .text:
            TextPlayground()
        case .textEditor:
            TextEditorPlayground()
        case .textField:
            TextFieldPlayground()
        case .timer:
            TimerPlayground()
        case .toggle:
            ToggleView(store: Store(initialState: ToggleFeature.State()) { ToggleFeature() })
        case .toolbar:
            ToolbarPlayground()
        case .tracking:
            TrackingPlayground()
        case .transform:
            TransformPlayground()
        case .transition:
            TransitionPlayground()
        case .videoPlayer:
            VideoPlayerPlayground()
        case .viewThatFits:
            ViewThatFitsPlayground()
        case .webView:
            WebViewPlayground()
        case .zIndex:
            ZIndexPlayground()
        }
    }
}

/// Holds the TCA Store in @State so it persists across re-renders of the parent view.
struct SQLFeaturePlaygroundView: View {
    @State var store = Store(initialState: SQLFeature.State()) { SQLFeature() }

    var body: some View {
        SQLView(store: store)
    }
}
