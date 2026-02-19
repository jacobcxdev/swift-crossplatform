<!-- Source: https://skip.dev/docs/gradle/ -->

# Skip Gradle Project Reference

## Overview

Skip uses Gradle as the Android build system (equivalent to SwiftPM for Darwin development). When building projects, Skip transpiles Swift code to Kotlin and converts `Package.swift` files into `build.gradle.kts` files. This creates an interconnected network of Gradle projects containing the entire dependency tree.

## Skip App Projects

A minimal app created via `skip init` contains:

### Swift Source Structure

- `Package.swift` - Standard SwiftPM package
- `Sources/[ModuleName]/` - Swift source files
- `Sources/[ModuleName]/Skip/skip.yml` - Module configuration
- `Android/` - Android-specific configuration

### Android Structure

- `Android/app/build.gradle.kts` - Top-level Gradle build config
- `Android/app/src/main/AndroidManifest.xml` - Android metadata
- `Android/gradle.properties` - Gradle settings
- `Android/settings.gradle.kts` - Root configuration

Running `swift build` generates translated output in `.build/plugins/outputs/[project]/[Module]/skipstone/`.

## Building Locally

### Command-Line Builds

#### Swift Package Build

```bash
swift build --build-tests
```

#### Gradle Unit Tests

```bash
skip gradle -p .build/plugins/outputs/[project]/[Module]/skipstone/[Module] test
```

#### Assemble APK

```bash
skip gradle -p Android/ assemble
```

#### Output Location

Debug and release APKs are placed in `.build/Android/app/outputs/apk/` directories.

**Configuration Note:** The Android build folder is configured by settings.gradle.kts to output to the root .build/Android/ folder.

## Skip Frameworks

Framework projects differ from app projects. Each Skip-enabled module requires a `Skip/skip.yml` YAML configuration file that describes Android/Gradle representation.

### Key Files

- `settings.gradle.kts` - Root project configuration
- `build.gradle.kts` - Module-level build configuration
- `skip.yml` - Skip-specific customization for dependencies and build mode

### Framework Build Outputs

Generated Gradle projects are considered ephemeral—cleaning or re-running the transpiler may override changes.

**Output Locations:**

- Command-line builds: `.build/plugins/outputs/` with package-named directories
- Xcode builds: `~/Library/Developer/Xcode/DerivedData/ProjectName-identifier/SourcePackages/plugins/`

Dependencies are referenced through symbolic links to local outputs, creating an interconnected project graph.

## Building APKs and AARs

### App Projects (APK)

Generate installable Android Package files using `gradle assemble` commands.

### Framework Projects (AAR)

Generate Android Archive files for publishing as reusable modules. Reference Gradle's "Publishing a project as module" documentation for details.

## Gradle Dependencies

All Skip app projects depend on five core Skip frameworks:

- SkipUI
- SkipModel
- SkipFoundation
- SkipLib
- SkipUnit

These are automatically transpiled in turn, resulting in a web of project links through relative symbolic references in Gradle.

### Dependency Management

Use `skip.yml` to add Java/Kotlin library dependencies beyond the core frameworks. Reference the Skip Core Framework `skip.yml` files as configuration examples.
