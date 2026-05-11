# Productbuilder

Productbuilder is a native SwiftUI macOS app for building distribution-style
`.pkg` installers with Apple's `pkgbuild` and `productbuild` tools.

It is intended for developers, release engineers, and macOS app maintainers who
need a lightweight, inspectable alternative to legacy package-authoring tools.
Productbuilder stores projects as JSON, stages payloads into component packages,
generates a Distribution XML file, and then creates the final installer product.

The idea is inspired by the excellent
[Packages](https://github.com/packagesdev/packages) project. Productbuilder can
import existing Packages `.pkgproj` files, so teams with established Packages
projects can reuse them instead of starting from an empty project.

Bundle identifiers:

- App: `ua.com.mcsim.productbuilder`
- CLI: `ua.com.mcsim.productbuilder.cli`

## Highlights

- Native macOS interface built with SwiftUI.
- Project files are readable JSON and can be saved, reopened, and built later.
- Multiple payload components in one product installer.
- Per-component package identifier, version, ownership mode, scripts, payloads,
  and Installer choice behavior.
- Payload entries can install a file or folder, install folder contents, or
  create an empty destination directory.
- Installer presentation resources: welcome, read me, license, conclusion,
  logo, light background, and dark Aqua background.
- Localized installer resources using standard `.lproj` folders.
- Install domain controls for local system, current user home, and anywhere.
- Optional minimum macOS version check in the generated Distribution XML.
- Optional Developer ID Installer signing identity.
- Keychain signing identity discovery in the app.
- Optional uninstall shell script generated beside the final `.pkg`.
- Best-effort import of existing Packages `.pkgproj` files.
- Live build log with the exact `pkgbuild` and `productbuild` commands.
- CLI target for building saved Productbuilder JSON projects in automation.

## Requirements

- macOS 13 or newer.
- Xcode 15 or newer recommended.
- Apple's command line tools, including `/usr/bin/pkgbuild` and
  `/usr/bin/productbuild`.
- A Developer ID Installer certificate is required only when signing packages.

The project has no third-party package dependencies.

## Repository Layout

```text
Productbuilder/
  ProductbuilderApp.swift        App entry point, menus, help, localization.
  ContentView.swift              Main SwiftUI interface.
  PackageProject.swift           Codable project model.
  PackageBuildService.swift      Staging, pkgbuild/productbuild, Distribution XML.
  ProjectDocument.swift          JSON open/save and Packages .pkgproj import.
  Assets.xcassets/               App icons and accent color.

ProductbuilderCLI/
  ProductbuilderCLI.swift        Command line entry point.

Productbuilder.xcodeproj/        Xcode project.
```

## Build From Source

Clone the repository and build the app:

```sh
xcodebuild \
  -project Productbuilder.xcodeproj \
  -scheme Productbuilder \
  -configuration Release \
  -derivedDataPath ./.DerivedData \
  build
```

The app will be placed under:

```text
.DerivedData/Build/Products/Release/Productbuilder.app
```

Build the CLI:

```sh
xcodebuild \
  -project Productbuilder.xcodeproj \
  -scheme productbuilder \
  -configuration Release \
  -derivedDataPath ./.DerivedData \
  build
```

The CLI binary will be placed under:

```text
.DerivedData/Build/Products/Release/productbuilder
```

## Using the App

1. Add or select a component in the sidebar.
2. Configure the component payload, destination paths, package identifier,
   version, ownership mode, choice behavior, and optional scripts.
3. Configure product metadata: name, identifier, version, output directory,
   install domains, minimum macOS version, signing identity, and uninstaller
   generation.
4. Add optional installer resources such as welcome/readme/license/conclusion
   pages, localized variants, logo, and backgrounds.
5. Use the preview tab to inspect the installer-facing presentation metadata.
6. Save the project as JSON and build the final `.pkg`.

## CLI Usage

After building the `productbuilder` target, build a saved project from the
terminal:

```sh
./.DerivedData/Build/Products/Release/productbuilder build path/to/project.json
```

Override the output directory stored in the project:

```sh
./.DerivedData/Build/Products/Release/productbuilder \
  build path/to/project.json \
  --output ~/Desktop
```

Legacy option names are also accepted:

```sh
productbuilder -build path/to/project.json -output ~/Desktop
```

## Project Files

Productbuilder project files are JSON documents encoded from the
`PackageProject` model. They include product metadata, components, payload
entries, installer resources, localization paths, signing settings, install
domains, and uninstaller preferences.

Project files may contain absolute local paths to payloads and resources. Review
saved JSON before committing it to a public repository if it was created from a
local machine.

## Packaging Model

During a build, Productbuilder:

1. Creates a temporary build workspace.
2. Stages each component payload at its configured destination path.
3. Runs `pkgbuild` for each component package.
4. Copies installer resources into a product resources directory.
5. Writes a Distribution XML file.
6. Runs `productbuild` to create the final product package.
7. Optionally writes an uninstall shell script beside the package.

Temporary staging directories are removed after the build completes.

## Localized Installer Resources

Each installer page can have a default resource plus language-specific variants.
Productbuilder copies localized files into standard `.lproj` bundles:

```text
Resources/Welcome.rtf
Resources/en.lproj/Welcome.rtf
Resources/uk.lproj/Welcome.rtf
Resources/fr.lproj/Welcome.rtf
```

The generated Distribution XML references `Welcome.rtf`, `ReadMe.rtf`,
`License.rtf`, and `Conclusion.rtf`; macOS Installer chooses the best localized
resource from the matching `.lproj` folder.

## Visual Branding

Productbuilder can attach Installer background artwork through Distribution XML:

```xml
<background file="background.png" scaling="proportional" alignment="left"/>
<background-darkAqua file="background-darkAqua.png" scaling="proportional" alignment="left"/>
```

The logo field copies a logo image into the product resources directory as
`Logo.*`. It can be reused by custom welcome, read me, license, or conclusion
resources.

## Legacy Packages Import

Productbuilder is inspired by
[Packages](https://github.com/packagesdev/packages), and one of its goals is to
make existing Packages projects useful in a modern, open SwiftUI app.

Use **Import Packages Project...** to convert a Packages `.pkgproj` file into a
Productbuilder project. The importer reads plist-based Packages projects and
maps product metadata, package identifiers, versions, payload hierarchy entries,
scripts, localized installer resources, background artwork, minimum macOS
requirements, and basic choice visibility/state.

If you already maintain installer projects in Packages, you can import those
`.pkgproj` files, review any import warnings in the build log, adjust the
resulting Productbuilder project if needed, and continue building packages from
there.

Some Packages-specific behavior is intentionally not converted yet, including
custom requirement plugins, locator plugins, imported prebuilt component
packages, and every proprietary presentation option. The importer logs warnings
for unsupported pieces that need manual review.

## Signing

Package signing is optional. When a Developer ID Installer identity is selected,
Productbuilder passes it to `productbuild` with `--sign`.

To inspect available installer signing identities manually:

```sh
security find-identity -v -p basic
```

Use a certificate whose common name starts with `Developer ID Installer` for
publicly distributed signed installer packages.

## Repository Hygiene

The repository intentionally ignores local and generated files such as:

- `.DS_Store` and other macOS Finder metadata.
- Xcode `xcuserdata/` and `*.xcuserstate` files.
- Derived data, local build directories, archives, reports, and dSYMs.
- SwiftPM local build state.
- Local `.env` files.
- Generated `.pkg`, `.mpkg`, uninstall scripts, logs, and temporary files.

Shared Xcode project files, source files, app assets, documentation, and license
files should remain tracked.

## Contributing

Ideas, issues, and pull requests are welcome. This project is open to practical
improvements from people who build macOS installers in real release workflows:
better Packages import coverage, installer presentation features, signing and
notarization workflows, CLI automation, tests, documentation, and UI refinements
are all useful directions.

For code changes, keep the project free of local machine state and generated
build products, and prefer small, focused changes that can be reviewed
independently.

Before opening a pull request, run at least:

```sh
xcodebuild \
  -project Productbuilder.xcodeproj \
  -scheme Productbuilder \
  -configuration Debug \
  -derivedDataPath ./.DerivedData \
  build
```

If your change affects CLI behavior, build the `productbuilder` scheme as well.

## License

Productbuilder is available under the MIT License. See [LICENSE](LICENSE).
