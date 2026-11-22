# Prep Report — Unsigned .ipa build for SideStore/AltStore sideloading

Prepared 2026-11-21. Goal: build the app on GitHub Actions into an
**unsigned** `.ipa` that SideStore/AltStore re-signs with a free Apple ID
at install time. This replaces the paid Apple Developer / TestFlight
route for personal use. No fake signing anywhere: CI produces a genuinely
unsigned app bundle; the device-side tool does the (legitimate, free
Apple ID) signing.

## Files created

- `MaqamTrainer.xcodeproj/project.pbxproj` — hand-authored Xcode project.
  One app target (`com.apple.product-type.application`) that compiles the
  existing sources directly from `Sources/MaqamTrainer/` (all 7 Swift
  files), uses `Sources/MaqamTrainer/Info.plist` as the real app
  Info.plist (`GENERATE_INFOPLIST_FILE = NO`, `INFOPLIST_FILE` set), and
  includes in its Resources phase:
  - `Assets.xcassets` — contains the `TeacherAvatar` imageset (already
    populated with `avatar.png`); `TeacherView` loads
    `UIImage(named: "TeacherAvatar")` from the main bundle, which is
    where the compiled catalog lands.
  - `TeacherAudio/` as a **folder reference**, copied verbatim into the
    .app so `TeacherAudio/manifest.json` resolves at runtime.
  - Deployment target iOS 16.0, Swift 5, bundle id
    **`com.abobakr.maqamtrainer`** (placeholder — change it in the target
    build settings and in Info.plist if a different id is wanted; keep
    the two in sync).
- `MaqamTrainer.xcodeproj/xcshareddata/xcschemes/MaqamTrainer.xcscheme` —
  shared scheme so `xcodebuild -scheme MaqamTrainer` works headlessly on
  a fresh checkout (its BlueprintIdentifier matches the target id in the
  pbxproj).
- `XcodeSupport/BundleModuleShim.swift` — compiled **only** by the Xcode
  project. `TeacherAudio.swift` looks files up in `Bundle.module` first;
  that accessor exists only in SwiftPM builds. The shim defines
  `Bundle.module` as `Bundle.main` for the app build (resources live at
  the .app root / in the `TeacherAudio/` subfolder there). It lives
  outside `Sources/MaqamTrainer/`, so the SPM target never sees it and
  there is no duplicate-definition clash.

## Files changed

- `.github/workflows/build.yml` — one job **added**; the existing SPM
  compile-verification job (`build`) is byte-for-byte untouched, and
  `Package.swift` is untouched.

Nothing was deleted. The web app was not touched.

## How the new CI job works

Job `unsigned-ipa` (runs on `macos-latest`, on push / manual dispatch):

1. `actions/checkout@v4`, prints the Xcode version.
2. `xcodebuild -list -project MaqamTrainer.xcodeproj` (early failure if
   the project/scheme is malformed).
3. `xcodebuild build -project MaqamTrainer.xcodeproj -scheme MaqamTrainer
   -configuration Release -destination 'generic/platform=iOS'`
   with `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`,
   `CODE_SIGN_IDENTITY=""` — a real compile + link producing an unsigned
   `MaqamTrainer.app` under `build/DerivedData/Build/Products/Release-iphoneos/`.
4. Packaging step: finds the `.app`, copies it into `Payload/`, and zips
   that as `MaqamTrainer-unsigned.ipa` (the standard .ipa layout), then
   lists the archive contents in the log.
5. `actions/upload-artifact@v4` uploads it as the workflow artifact
   **`MaqamTrainer-unsigned-ipa`**.

## What will happen on the first run

- Both jobs run in parallel: the old SPM job should pass exactly as
  before (run #6 did); the new job exercises the hand-authored project
  for the first time on a real Xcode.
- If the new job succeeds, the run page offers the
  `MaqamTrainer-unsigned-ipa` artifact for download. That .ipa is what
  gets handed to SideStore/AltStore on the iPhone, which re-signs it
  with the free Apple ID and installs it. Free-Apple-ID installs expire
  after 7 days and are refreshed by SideStore/AltStore in the
  background — expected behaviour of this route, not a build problem.
- The app will run with the Arabic mic-permission prompt from
  Info.plist (`NSMicrophoneUsageDescription`) the first time the coach
  opens the microphone.

## Known risks (first CI run is the real test)

- **Hand-authored pbxproj details.** The file was validated locally for
  structure (balanced delimiters, all sections present, every referenced
  file exists on disk, scheme id matches), but only real `xcodebuild`
  can prove it end-to-end. The most likely first-run failures are minor
  project-format nits (a missing default build setting Xcode wants, or
  the `-list` step revealing a scheme issue) — each is a small,
  one-line fix in the pbxproj/scheme.
- **`Bundle.module` shim.** If a future Xcode/Swift version generates
  its own accessor for app targets, the shim would clash and CI would
  fail with a duplicate-definition error — fix would be deleting the
  shim from the Sources phase. Not expected on current Xcode.
- **No app icon.** The asset catalog has no `AppIcon.appiconset`, so the
  installed app shows the default placeholder icon. Cosmetic only;
  adding an icon later means dropping an `AppIcon.appiconset` (1024px
  image) into `Assets.xcassets` — no project change needed.
- **Folder-reference resources.** `TeacherAudio/` is copied as a folder;
  if a future Xcode treats the folder reference differently, the teacher
  tab would show «الدرس الصوتي بيتحضّر» (its designed no-audio state)
  while the rest of the app works — a graceful failure, easy to spot.
- **Validation limits here.** This VM has no Swift toolchain, so
  `swift package dump-package` could not be run; Package.swift was not
  modified at all, so the SPM manifest is exactly the one CI already
  passed with.

## Next steps (need the main agent's browser — GitHub)

1. Commit and push the new/changed files:
   `MaqamTrainer.xcodeproj/`, `XcodeSupport/BundleModuleShim.swift`,
   `.github/workflows/build.yml`, and this report.
2. Open the repo's Actions tab and watch the run: confirm job `build`
   still passes and watch job `unsigned-ipa`.
3. If `unsigned-ipa` fails, read its first failing step's log (the
   `-list` step and the build step print the relevant errors) and fix
   the pbxproj/scheme accordingly, then re-push.
4. On success, download the `MaqamTrainer-unsigned-ipa` artifact from
   the run page and hand the .ipa to the user for SideStore/AltStore
   installation with his free Apple ID.
