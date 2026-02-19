<!-- Source: https://skip.dev/docs/development-topics/ -->
# Common Development Topics

## Configuration with Skip.env

Skip app customization should be primarily done by directly editing the included `Skip.env` file, rather than changing the app's settings in Xcode. Only properties set in `Skip.env`, such as `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER` and `MARKETING_VERSION`, carry through to both `HelloSkip.xcconfig` and `AndroidManifest.xml`.

## Localization

### Overview
Localizing your app into multiple languages maximizes reach and accessibility. Skip embraces the `xcstrings` catalog format (new in Xcode 15) to provide a simple solution for adding multi-language support.

### Localization Example
SwiftUI text components like `Text("Hello \(name)!")` and `Label("Welcome", systemImage: "heart.fill")` can be localized by editing the `Localizable.xcstrings` file.

For non-SwiftUI strings, use the standard `NSLocalizedString` function:

```swift
let localizedTitle = NSLocalizedString("License key for %@")
sendLicenseKey(key, to: user, title: String(format: localizedTitle, user.fullName))
```

### The xcstrings Format
The `Localizable.xcstrings` file is a JSON file located at `Sources/HelloSkip/Resources/Localizable.xcstrings`. Xcode 15 will automatically fill in any strings that it finds in common SwiftUI components.

Supported substitution tokens:
- `$@` - String or stringified instance
- `%ld` or `%lld` - Integer number
- `%lf` or `%llf` - Floating point number
- `%.3f` - Formatted floating point
- `%1$@` - Manually-specified positional argument
- `%%` - Literal escaped percent sign

Sample structure:
```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Hello %@!" : {
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "¡Hola %@!"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

### Localizing Modules
When modularizing your app into separate SwiftPM modules, use the `Bundle` parameter explicitly:

```swift
VStack {
    Text("Hello \(name)!", bundle: .module)
    Button {
        doSomething()
    } label: {
        Text("Click Me", bundle: .module)
    }
}
```

For `NSLocalizedString`:
```swift
let localizedTitle = NSLocalizedString("License key for %@", bundle: .module)
```

### Limitations
Skip does not currently handle String Catalog Plural Variants.

## Notifications

Skip supports the core API of Apple's `UserNotifications` framework for iOS notification handling across platforms. Firebase support includes push messaging. Use deep links to take users to particular app locations.

```swift
public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let content = response.notification.request.content
    if let deepLink = content.userInfo["deep_link"] as? String, let url = URL(string: deepLink) {
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }
}
```

## Deep Links

Deep links bring users to particular app locations. Skip supports custom URL schemes and SwiftUI deep link handling.

### Darwin Setup
Register your custom URL scheme in Xcode following Apple's instructions.

### Android Setup
Edit `AndroidManifest.xml` to add an `intent-filter` for your custom URL scheme:

```xml
<manifest ...>
    <application ...>
        <activity ...>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.BROWSABLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="myurlscheme" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

Android will expect deep link URLs with the general form `scheme://host` or `scheme://host/path`.

### SwiftUI Deep Link Processing
Use the `onOpenURL` view modifier to intercept and process deep links:

```swift
enum Tab : String {
    case cities, favorites, settings
}

public struct ContentView: View {
    @AppStorage("tab") var tab = Tab.cities
    @State var cityListPath = NavigationPath()

    public var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $cityListPath) {
                CityListView()
            }
            .tag(Tab.cities)
            NavigationStack {
                FavoriteCityListView()
            }
            .tag(Tab.favorites)
            SettingsView()
            .tag(Tab.settings)
        }
        .onOpenURL { url in
            if let tabName = url.host(), let tab = Tab(rawValue: tabName) {
                self.tab = tab
                if tab == .cities, let city = city(forName: url.lastPathComponent) {
                    DispatchQueue.main.async {
                        cityListPath.removeLast(cityListPath.count)
                        cityListPath.append(city.id)
                    }
                }
            }
        }
    }
}
```

### Testing
On iOS, test by entering a URL into Safari or embedding it in Calendar events or Notes.

On Android, use adb:
```
adb shell am start -W -a android.intent.action.VIEW -d "travel://cities/London"
```

## singleTop

By default on Android, tapping a notification or deep link initializes a new app instance. To maintain iOS-like behavior, use the `singleTop` launch mode in `AndroidManifest.xml`:

```xml
<activity android:launchMode="singleTop">
```

## Resources

Place shared resources in `Sources/ModuleName/Resources/`. Skip copies these files to Android builds and makes them available through standard `Bundle` APIs:

```swift
let resourceURL = Bundle.module.url(forResource: "sample", withExtension: "dat")
let resourceData = Data(contentsOf: resourceURL)
```

Unlike Darwin platforms, where resources are stored as individual files on disk, Android resources remain in their containing APK when the app is installed. Use only `Bundle.module.url(forResource:)` on Android; `Bundle.module.path(forResource:)` will raise an exception.

### Colors, Fonts, Images
Skip supports named colors from asset catalogs, custom fonts, iOS asset catalogs with PNG/JPG/PDF, Google Material Icons, SF Symbols SVGs, network images, and bundled image files. See SkipUI module documentation.

### App Icons
Generate and update icons using the `skip icon` CLI command:
```
skip icon --open-preview --foreground white --random-background symbol.svg
```

## Themes

Skip fully supports iOS and Android system color schemes, as well as SwiftUI styling modifiers like `.background`, `.foregroundStyle`, `.tint`, and so on.

For Android-only customization beyond SwiftUI's standard modifiers, Skip provides additional API detailed in SkipUI's Material topic.

Note: Material SwiftUI modifiers for Skip Fuse are currently a work in progress and only supported for Skip Lite apps.
