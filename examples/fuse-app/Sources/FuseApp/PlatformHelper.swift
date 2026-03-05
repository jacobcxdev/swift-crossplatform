// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from skipapp-showcase-fuse PlatformHelper.swift

import Foundation
import SkipFuse

#if os(Android)
let isAndroid = true
#else
let isAndroid = false
#endif

/// The name of the current app.
let appName = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
    ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
    ?? "Unknown"

/// The current version of the app, using the main bundle's infoDictionary
/// `CFBundleShortVersionString` property on iOS and
/// `android.content.pm.PackageManager` `versionName` on Android.
let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    ?? "0.0.0"

/// The bundle identifier of the current app.
let appIdentifier = (Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String)
    ?? "app.unknown"
