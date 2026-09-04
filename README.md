# Chalkak

[한국어](README.ko.md)

Screenshots of your real iOS app, on every push, without a Mac and without writing a single UI test.

Chalkak takes the simulator `.app` your CI already builds, boots a simulator, walks through your screens using launch
arguments, and uploads the shots as an artifact with a browsable gallery. Your app source is not modified.

It was built to close one specific gap: you can build an iOS app from Windows using a macOS runner, but until you ship
a TestFlight build you cannot see what any screen actually looks like. The first sweep it ran on a real app found a
layout bug that only appeared in English, in a screen nobody had looked at in that language.

- **Cost**: the macOS runner minutes you already spend, plus 1 to 5 minutes of simulator boot and roughly 10 seconds
  per shot. Free on a public repo.
- **Not for**: touch interaction, haptics, widgets, lock screen, performance. This is for layout, color, typography,
  dark mode and localization.

## Usage

Add it after your build step. Note the signing flags, they matter more than they look; see [Traps](#traps).

```yaml
- name: Build for simulator
  run: |
    xcodebuild build -project MyApp.xcodeproj -scheme MyApp \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/dd \
      CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO

- uses: Yewon419/chalkak@v1
  with:
    app: build/dd/Build/Products/Debug-iphonesimulator/MyApp.app
    defaults: |
      onboardingDone -bool true
    screens: |
      # name | launch arguments (they land in the UserDefaults argument domain)
      today       | -rootTab today
      settings    | -rootTab settings
      settings-ja | -rootTab settings -AppleLanguages (ja)
    appearance: light,dark
    privacy: location
```

You get a `screenshots` artifact containing `<name>-<appearance>.png`, a `summary.md`, and an `index.html` gallery.
A table of every shot is also appended to the job summary. Unzip and open `index.html` for a phone-proportioned grid,
click any shot for full size.

## How screens are reached

Chalkak never modifies your app. It uses two paths only.

1. **Launch arguments**, written as `-key value`. These land in the `UserDefaults` argument domain, which wins over
   the application domain on read. `@AppStorage` reads them too. Good for string keys such as a selected tab, theme,
   or language.
2. **Pre-injected defaults**, via `xcrun simctl spawn <udid> defaults write <bundle-id> <key> <value>`, applied before
   the first launch. Safer for boolean flags such as "onboarding completed", because a launch argument's `YES` string
   is not guaranteed to be read as a `Bool` by `@AppStorage`.

If your app overwrites a key at launch (for example resetting to the first tab on every start), only path 1 works,
because the argument domain still wins on read.

If your app has no such keys, add a small debug-only router that reads launch arguments. That is the only case where
Chalkak needs anything from your codebase.

## Inputs

| Input | Default | Description |
|---|---|---|
| `app` | required | Path to the simulator `.app` |
| `screens` | required | One screen per line, `name \| launch arguments`. Arguments optional. `#` starts a comment |
| `defaults` | `''` | One per line, passed verbatim after `defaults write <bundle-id>` |
| `appearance` | `light` | `light`, `dark`, or `light,dark` |
| `device` | `''` | Substring of a device name. Empty picks the first iPhone on the newest iOS runtime |
| `runtime` | `''` | Runtime filter such as `iOS 26`. Empty picks the newest |
| `wait` | `5` | Seconds between launch and capture. Raise it if you have a long splash |
| `output-dir` | `screenshots` | Output directory |
| `artifact-name` | `screenshots` | Uploaded artifact name |
| `upload` | `true` | Whether to upload the artifact |
| `fail-on-crash` | `true` | Fail the step if the app was not running at capture time |
| `bundle-id` | `''` | Empty reads `CFBundleIdentifier` from `Info.plist` |
| `title` | `''` | Gallery title. Empty uses `<executable> 찰칵` |
| `privacy` | `''` | Permissions to pre-grant, comma separated, using `simctl privacy` service names (`location`, `photos`, `all`, ...) |

## Traps

These are the things that cost real time to discover. They are the reason this repo exists.

**Entitlements must be set at build time, not after.** Simulator entitlements are embedded by the linker into the
binary's `__TEXT,__entitlements` section. Build with `CODE_SIGNING_ALLOWED=NO` and that section is absent, so an app
using CloudKit dies at `CKContainer(identifier:)` with `EXC_BREAKPOINT`. The fix is to sign the simulator build ad-hoc,
which needs no certificate and no provisioning profile:

```sh
xcodebuild build ... -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

Injecting entitlements afterwards with `codesign --entitlements` does not work. The host macOS taskgated kills an
ad-hoc process carrying restricted entitlements: `SIGKILL (Code Signature Invalid)`, termination
`CODESIGNING / Taskgated Invalid Signature`. This is why Chalkak does not touch signing at all. No iCloud account is
needed on the simulator; container init succeeds and only sync logs a failure.

**A system permission alert survives app relaunch and covers every later shot.** One location prompt hid 22 of 44 shots
in a single run. Pre-grant with the `privacy` input. Notifications and HealthKit are not offered by `simctl privacy`,
so for those put the screen that triggers them last.

**Never hardcode a device name.** Runner images change and you get `device not found`
([actions/runner-images#10960](https://github.com/actions/runner-images/issues/10960)). Chalkak picks from the live
runtime list instead.

**In bash, a Korean or other multibyte word directly after `$var` is parsed as part of the variable name.** Always
write `${var}`. This produced `crashed?: unbound variable` at the very end of an otherwise successful run.

Smaller ones:

- First simulator boot on a runner took up to 5 minutes. Each shot after that is about 10 seconds.
- If the app was not running at capture time, `summary.md` marks it and any crash report lands in `crash/`. A shot of
  the home screen means exactly that.
- `status_bar override` may not apply on some device and runtime combinations. Capture continues either way.
- Artifact images cannot be inlined into a PR comment. Download the zip, or publish the gallery (below).

## Viewing the gallery in a browser

Artifacts have to be downloaded to be opened. To get one stable link that always shows the latest run, publish the
output directory to GitHub Pages. Free on a public repo.

```yaml
- uses: Yewon419/chalkak@v1
  with:
    app: ...
    screens: ...
- uses: peaceiris/actions-gh-pages@v4
  if: always()
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: screenshots
```

The job needs `permissions: contents: write`, and Pages must be pointed at the `gh-pages` branch once in repository
settings. After that `https://<user>.github.io/<repo>/` is always the latest gallery. Note that Pages is public, so
your screenshots are public too.

For a single self-contained HTML file with the images inlined as data URIs:

```sh
gh run download <run-id> -n screenshots -D shots
python3 scripts/inline_gallery.py shots gallery.html
```

## Running locally on a Mac

```sh
APP=build/dd/Build/Products/Debug-iphonesimulator/MyApp.app \
SCREENS=$'today | -rootTab today\nsettings | -rootTab settings' \
DEFAULTS='onboardingDone -bool true' \
scripts/shoot.sh
```

The simulator is left running unless you set `SHUTDOWN=true`. On a rerun against the same simulator, `defaults` can
lose to the already-running app's preference cache; `xcrun simctl uninstall booted <bundle-id>` first for a clean state.

## Requirements

A macOS runner with Xcode, which is what `runs-on: macos-latest` already gives you. Nothing else, no dependencies.

## License

MIT
