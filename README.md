# Productbuilder

Productbuilder is a SwiftUI macOS tool for creating distribution-style `.pkg` products with Apple's `pkgbuild` and `productbuild`.

Bundle identifier: `ua.com.mcsim.productbuilder`

## Current Features

- Product metadata: name, identifier, version, output directory.
- Multiple payload components.
- Per-component source path and destination path.
- Per-component package identifier, version, and ownership mode.
- Per-component choice behavior: required, selected by default, visible.
- Optional preinstall and postinstall scripts.
- Installer screens: welcome, read me, license, and conclusion resources.
- Localized installer screen resources using `.lproj` folders.
- Visual branding resources: logo asset, light background, and dark Aqua background.
- Install domains: local system, current user home, and anywhere.
- Optional minimum macOS version check in Distribution XML.
- Optional product resources directory for `productbuild`.
- Optional Developer ID Installer signing identity, with Keychain identity discovery.
- Optional generated uninstall shell script beside the final `.pkg`.
- JSON save/open for project configuration.
- Best-effort import for legacy Packages `.pkgproj` files.
- Live build log with the exact commands executed.

## Legacy Packages Import

Use **Import Packages Project...** to convert a legacy Packages `.pkgproj` into a Productbuilder project. The importer reads plist-based Packages projects and maps product metadata, package identifiers, versions, payload hierarchy entries, scripts, localized welcome/readme/license resources, background artwork, minimum macOS requirements, and basic choice visibility/state.

Some Packages-specific behavior is intentionally not converted yet, including custom requirement plugins, locator plugins, imported prebuilt component packages, and every proprietary presentation option. The importer logs warnings for unsupported pieces that need manual review.

## Build

```sh
xcodebuild -project Productbuilder.xcodeproj -scheme Productbuilder -configuration Debug build
```

## Packaging Model

Each component is staged into a temporary root at its configured destination path, then converted into a component package with `pkgbuild`. Productbuilder then writes a Distribution XML and creates the final product package with `productbuild`.

## Localized Installer Pages

Each installer page can have a default resource plus language-specific variants. During build, Productbuilder copies localized files into the product resources directory as standard `*.lproj` bundles, for example:

```text
Resources/Welcome.rtf
Resources/en.lproj/Welcome.rtf
Resources/uk.lproj/Welcome.rtf
Resources/fr.lproj/Welcome.rtf
```

The Distribution XML continues to reference `Welcome.rtf`, `ReadMe.rtf`, `License.rtf`, and `Conclusion.rtf`; macOS Installer chooses the best localized resource from the matching `.lproj` folder.

## Visual Branding

Productbuilder can attach Installer background artwork through Distribution XML:

```xml
<background file="background.png" scaling="proportional" alignment="left"/>
<background-darkAqua file="background-darkAqua.png" scaling="proportional" alignment="left"/>
```

The logo field copies a logo image into the product resources directory as `Logo.*`. It can be reused by custom welcome/readme resources or by a future generated welcome template.
