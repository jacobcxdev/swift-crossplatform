#if !SKIP
import ComposableArchitecture
import Testing

// MARK: - Test Action

enum TestAlertAction: Equatable {
    case confirm
    case delete
    case cancel
}

// MARK: - Tests

@MainActor
@Suite("TextState and ButtonState Parity Tests")
struct TextStateButtonStateTests {

    // MARK: - TextState

    @Test("TextState preserves plain text content")
    func textStatePlainText() {
        let text = TextState("Hello")
        #expect(String(state: text) == "Hello")
    }

    @Test("TextState concatenation produces correct combined text")
    func textStateConcatenation() {
        let combined = TextState("Hello, ") + TextState("World!")
        #expect(String(state: combined) == "Hello, World!")
    }

    @Test("TextState with verbatim initializer preserves content")
    func textStateVerbatim() {
        let text = TextState(verbatim: "Verbatim text")
        #expect(String(state: text) == "Verbatim text")
    }

    @Test("TextState equality for identical strings")
    func textStateEquality() {
        let a = TextState("Same")
        let b = TextState("Same")
        #expect(a == b)
    }

    @Test("TextState inequality for different strings")
    func textStateInequality() {
        let a = TextState("One")
        let b = TextState("Two")
        #expect(a != b)
    }

    #if !os(Android)
    @Test("TextState with formatting still contains original text")
    func textStateWithFormatting() {
        // On macOS/iOS, bold/italic add modifiers but String(state:) still extracts plain text.
        // On Android, bold/italic modifiers are unavailable due to CGFloat ambiguity between
        // Foundation and SkipSwiftUI -- importing SkipSwiftUI in TextState.swift causes type
        // conflicts. TextState stores verbatim text only on Android; plain text extraction works.
        let bold = TextState("Bold").bold()
        #expect(String(state: bold) == "Bold")

        let italic = TextState("Italic").italic()
        #expect(String(state: italic) == "Italic")

        let boldItalic = TextState("Both").bold().italic()
        #expect(String(state: boldItalic) == "Both")
    }
    #endif

    @Test("TextState multi-segment concatenation")
    func textStateMultiConcatenation() {
        let text = TextState("A") + TextState("B") + TextState("C")
        #expect(String(state: text) == "ABC")
    }

    // MARK: - ButtonState

    @Test("ButtonState with destructive role stores role and action correctly")
    func buttonStateDestructive() {
        let button = ButtonState(role: .destructive, action: TestAlertAction.delete) {
            TextState("Delete")
        }
        #expect(button.role == .destructive)
        #expect(button.action.action == .delete)
        #expect(button.label == TextState("Delete"))
    }

    @Test("ButtonState with cancel role")
    func buttonStateCancel() {
        let button = ButtonState<TestAlertAction>(role: .cancel) {
            TextState("Cancel")
        }
        #expect(button.role == .cancel)
        #expect(button.action.action == nil)
        #expect(button.label == TextState("Cancel"))
    }

    @Test("ButtonState with default role (nil)")
    func buttonStateDefaultRole() {
        let button = ButtonState(action: TestAlertAction.confirm) {
            TextState("OK")
        }
        #expect(button.role == nil)
        #expect(button.action.action == .confirm)
        #expect(button.label == TextState("OK"))
    }

    @Test("ButtonState withAction invokes closure with correct action")
    func buttonStateWithAction() {
        let button = ButtonState(action: TestAlertAction.delete) {
            TextState("Delete")
        }
        var receivedAction: TestAlertAction?
        button.withAction { action in
            receivedAction = action
        }
        #expect(receivedAction == .delete)
    }

    // MARK: - AlertState

    @Test("AlertState preserves title and message TextState")
    func alertStateTitleAndMessage() {
        let alert = AlertState<TestAlertAction> {
            TextState("Error Occurred")
        } message: {
            TextState("Please try again later.")
        }
        #expect(String(state: alert.title) == "Error Occurred")
        #expect(String(state: alert.message!) == "Please try again later.")
    }

    @Test("AlertState with buttons has correct count and actions")
    func alertStateWithButtons() {
        let alert = AlertState<TestAlertAction> {
            TextState("Confirm Delete")
        } actions: {
            ButtonState(role: .destructive, action: .delete) {
                TextState("Delete")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState("This cannot be undone.")
        }

        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[0].role == .destructive)
        #expect(alert.buttons[0].action.action == .delete)
        #expect(alert.buttons[0].label == TextState("Delete"))
        #expect(alert.buttons[1].role == .cancel)
        #expect(alert.buttons[1].label == TextState("Cancel"))
    }

    @Test("AlertState equality for identical alerts")
    func alertStateEquality() {
        let makeAlert = {
            AlertState<TestAlertAction> {
                TextState("Title")
            } actions: {
                ButtonState(action: .confirm) {
                    TextState("OK")
                }
            }
        }
        #expect(makeAlert() == makeAlert())
    }
}
#endif
