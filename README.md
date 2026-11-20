# مدرب المقامات والبيانو — Native iOS App

A native SwiftUI maqam trainer, built the way native App Store apps are
built: the microphone is accessed directly through AVAudioSession +
AVAudioEngine (no browser, no web view), so live listening works like
in Yousician-style apps.

## What's inside

- **المدرب اللايف (Live coach)** — pick one of the 9 maqams, sing or play
  into the mic, and get corrected live: detected note name (English A–G),
  cents deviation from the nearest scale degree (quarter-tone exact,
  50-cent steps), a −50…+50 cents bar, a green «صح» state within
  ±15 cents of the target degree, a target-step advance button, a
  «اسمع السلّم» button (the scale played up/down at 0.6 s per note with
  pitch-exact tones, quarter tones included), and a live level meter.
- **المدرّس (AI teacher)** — a virtual teacher persona created by AI.
  The teacher *sings* each maqam (scale up/down on "آه", then a short
  phrase) from bundled audio files, with an avatar slot (asset name
  `TeacherAvatar`) and a written Arabic lesson line per maqam.
- **المقامات** — reference list: tonic, English degree names, character.
- **البيانو** — the selected maqam's scale as tappable keys that play
  pitch-exact tones.

There are **no external videos, embeds, or links** in this app by
design — all content is bundled.

## Teacher audio (drop-in)

Teacher audio files will be produced and pitch-verified separately and
dropped into `Sources/MaqamTrainer/TeacherAudio/`:

- `manifest.json` maps each maqam id to two files:
  `<maqam>-scale.m4a` (scale sung up/down on "آه") and
  `<maqam>-phrase.m4a` (short sung phrase ending on the tonic).
- No code change is needed when files are added or replaced.
- While a file is missing, the teacher tab shows «الدرس الصوتي بيتحضّر»
  and still shows the written lesson.

## How CI builds it

This is a Swift Package (swift-tools 5.9, iOS 16+). On every push,
GitHub Actions (`.github/workflows/build.yml`) runs on a macOS 14
runner:

```
xcodebuild build -scheme MaqamTrainer \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

That build is **compile-verification only**: it proves the code builds
with the iOS SDK on a real Mac toolchain. It does not produce an
installable signed app.

### Info.plist note

`Sources/MaqamTrainer/Info.plist` carries
`NSMicrophoneUsageDescription` (the Arabic mic-permission prompt). It is
excluded from the SPM target because SwiftPM cannot place an Info.plist
at an app-bundle root; when the package is wrapped in a regular Xcode
app project for distribution, that plist becomes the app's Info.plist.

## Next step: TestFlight

Signing and TestFlight distribution come **after** enrollment in the
Apple Developer Program (the account holder enrolls with their own
Apple ID). Once enrolled, the same sources are wrapped in an Xcode app
target with the bundle id from Info.plist, signed with the team
certificate, archived, and uploaded to App Store Connect / TestFlight.
