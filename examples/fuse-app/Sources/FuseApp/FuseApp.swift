// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import Dependencies
import Foundation
import IssueReporting
import SkipFuse
import SwiftUI

/// A logger for the FuseApp module.
let logger: Logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "FuseApp")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `AppView` for the app and logs a message.
/* SKIP @bridge */public struct FuseAppRootView : View {
    let store: StoreOf<AppFeature> = {
        #if DEBUG
        Store(initialState: AppFeature.State()) { AppFeature()._printChanges() }
        #else
        Store(initialState: AppFeature.State()) { AppFeature() }
        #endif
    }()

    /* SKIP @bridge */public init() {
        prepareDependencies {
            do {
                try $0.bootstrapDatabase()
            } catch {
                reportIssue(error)
            }
        }
    }

    public var body: some View {
        AppView(store: store)
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class FuseAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = FuseAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
