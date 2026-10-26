# Dopamine wallpaper workspace

## Scope

Imported from roothide/Dopamine-roothide, branch `3.x`, baseline commit
`24ea745b33cd3a1eba9b7196a875e42eed1fa34e`. This change adds app-background UI only.
Do not alter jailbreak, security, injection, exploit, entitlement or signing behavior.
On 2026-10-27 the user authorized pushing these changes to their GitHub account
and compiling with GitHub Actions, including the cloud build's required dependencies.
Installation, launching Dopamine, respring and reboot remain unauthorized.
Do not install Theos or download build dependencies onto this device.

## Source identity

- Xcode app settings: marketing version `3.0.12`, build `1`, bundle identifier
  `com.opa334.Dopamine`.
- `BaseBin/_external/basebin/.version` is `3.0.12`; `.version-roothide` is `28`.
- `Application/Makefile` rewrites the packaged version to `3.0.12-28` and the
  packaged identifier to `com.opa334.Dopamine-roothide`.
- The user reports installed identifier `cn.zqbb.dopaRH`, version `3.0.12-28`,
  build `1`. Matching version strings do NOT establish identical source or binary
  provenance; the packaged identifier differs. Do not claim an exact match.

## Wallpaper implementation

- `Application/Dopamine/UI/DOMainViewController.m`: first action, 自定义壁纸.
- `DOWallpaperController.{h,m}` in the same directory: Chinese settings menu,
  PHPicker single-image selection, cancellation, serial utility-queue processing,
  atomic protected save, startup reload and restore-default.
- `DOWallpaperImage.{h,m}`: ImageIO thumbnail longest edge <=2048 pixels,
  input <=64 MiB, <=120 million pixels, each dimension <=50000; applies orientation;
  re-encodes pixels as JPEG without copying source EXIF/GPS metadata.
- Storage is resolved with Foundation within the app's Application Support directory:
  `DOWallpaper/wallpaper.jpg`. No hard-coded container UUID or bootstrap path.
  Because upstream has no-sandbox entitlements, storage fails closed unless the
  resolved home has an app-container UUID under Containers/Data/Application and
  the resolved wallpaper paths remain inside it. An unusual launch environment
  may therefore disable wallpaper persistence with an error; verify at runtime.
- `DONavigationController.{h,m}`: owns the controller, aspect-fill background,
  black 65% readability overlay; restore uses the currently enabled built-in theme.
- `Application/Dopamine.xcodeproj/project.pbxproj`: registers both new implementation
  files and PhotosUI/ImageIO/UniformTypeIdentifiers in both app configurations.
- Cancellation invalidates the operation before decoding/saving when possible.
  If the atomic save has already committed, cancellation reloads that committed
  image; it is not an undo operation.

## Reproducible local checks

Run from the repository root with Apelin's prepared clang and SDK environment:

```sh
sh Tests/check-wallpaper-compile.sh
```

This script performs ONLY object compilation and test-binary linking. It does not
install, sign, run or package an app, and does not fetch dependencies. Output goes
under the existing ignored `.build/wallpaper` directory.

Verified with Command Line Tools 27.0 / iPhoneOS SDK 27.0, deployment target 15.0:
- DOWallpaperImage and DOWallpaperController compile with strict warnings for
  arm64 and arm64e.
- DONavigationController compiles for both architectures; an existing bundled
  Preferences header emits a UIPopoverController deprecation warning.
- Tests/WallpaperImageTests.m links for both architectures.

This does NOT compile DOMainViewController or link the application. The earlier
main-controller attempt stopped at missing `choma/CodeDirectory.h`. Do not add fake
headers/stubs to make an application check appear to pass.

An earlier signed standalone image-test execution exited 137 without output.
No crash report was returned. Its cause is unconfirmed; no runtime assertions
may be reported as passed. The compile-check script deliberately does not run it.

## Full build: blocked on this device

The root Makefile builds BaseBin, Packages and Application. Application/Makefile
uses xcodebuild and packages IPA/TIPA. BUILD.md describes the upstream GitHub Actions
route; .github/workflows/main.yml uses macOS, Xcode, GNU Make, Theos, trustcache and
recursive submodules. Checkout now uses the triggering repository rather than
explicitly fetching upstream, so the intended workflow includes local wallpaper edits.
The xz SDK extraction has also been corrected. Cloud execution is not yet verified.

This device has clang/ld/ldid but lacks xcodebuild, make/gmake, Swift, xcrun, actool,
ibtool and trustcache. ChOma, XPF, opainject and litehook submodule directories are
empty. Theos must not be installed here. Do not invent an Apelin external packaging
script or claim an IPA build from the compile-only check. No full build has passed.
A local commit is authorized to hand the changes to GitHub Actions despite the
unavailable full local build. Do not describe that commit as a successful app build.
GitHub account in Apelin is mowang7426; origin still points to the upstream repository.
The available tools cannot create a fork, add/set a remote, or dispatch/query Actions;
no push or cloud build has succeeded yet.

## Pending acceptance checks

On an authorized complete build/test environment, verify the source/project parses
and full app compilation/linking/assets first. Then obtain authorization before
installation or app launch. Test the following without invoking jailbreak actions:

- Chinese entry visible, unobstructed and enabled; small iPhone/iPad, rotation,
  larger text, VoiceOver; original menu and jailbreak button layout unaffected.
- JPEG, PNG, HEIC, orientation, transparency and large images; aspect-fill crop.
- Picker cancel, progress cancel, iCloud failure, corrupt/oversized/missing input;
  old saved image preserved on failure, no stale completion after cancellation.
- Persist across relaunch, repeatedly restore default (including absent file),
  current built-in theme restored, storage/protection failures handled.
- Bright-image readability, menu transitions, repeated imports, bounded memory
  and responsive UI; test binaries must actually run before claiming assertions pass.
