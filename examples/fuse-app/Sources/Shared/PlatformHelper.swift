// Copyright 2023–2025 Skip
import Foundation
import SkipFuse

#if os(Android)
public let isAndroid = true
#else
public let isAndroid = false
#endif

/// The name of the current app
public let appName = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "Unknown"

/// The current version of the app, using the main bundle's infoDictionary `CFBundleShortVersionString` property on iOS and `android.content.pm.PackageManager` `versionName` on Android.
public let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"

/// The bundle identifier of the current app
public let appIdentifier = (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String) ?? "app.unknown"
