# Am I Shouting?

A small level meter in the macOS menu bar. It learns the room's noise floor,
compares your voice against it, and tells you by colour whether you are
shouting.

```
[▬▬▬▬▬▭|▭]   green = normal · yellow = loud · red = shouting
```

No Dock icon, no window. Audio is never recorded or sent anywhere. The UI is in
English and can be switched to Türkçe from the popover.

## Install

Download the latest `.dmg` from the [releases page][releases], open it, and drag
**Am I Shouting?** to Applications.

> **First launch.** Releases are not signed with an Apple Developer ID yet, so
> macOS refuses to open the app and says it cannot verify the developer. Try to
> open it once, then go to **System Settings → Privacy & Security**, find the
> message about "Am I Shouting?" and choose **Open Anyway**. Once only.

## Calibrate it first

Do this before anything else. The default thresholds are a guess: they know
nothing about your microphone, your voice, or how far you sit from the laptop,
and until you fix that the colours will be wrong for you.

1. Allow microphone access when asked.
2. Click the bar in the menu bar, press **Measure my normal voice**.
3. Speak at your normal level for five seconds.

The thresholds are rebuilt around your own voice and saved. It takes five
seconds and it is the difference between a meter that works and one that cries
wolf. Do it again if you switch microphone or move somewhere very different.

The rest of the panel: live dB readings, a **Sensitivity** trim (−8…+8 dB,
right flags you earlier), the language switch, and **Pause**.

## How it works

A single microphone cannot separate "the room" from "your voice" — it hears both
at once. So the app measures what it actually can: **how many dB above the
room's noise floor you are.** A level that counts as shouting in a silent office
is an ordinary speaking voice in a busy café.

The floor is the 10th percentile of the last 12 seconds, because the gaps
between words are what the room sounds like. It may only rise at ~3 dB/s, so
sustained shouting never quietly becomes "ambient". Your own level is the 80th
percentile of the last 0.8 seconds, so a door slam is too brief to raise the
alarm on its own. A verdict escalates in 0.15 s but calms down over 0.9 s, so
the colour does not flicker between words.

## Known limits

- **AirPods and similar headsets** apply their own noise and echo cancellation,
  so the noise floor reads quieter than the real room. Calibration compensates.
- **No speech recognition.** Any sustained sound loud enough counts as speech: a
  radiator, an air conditioner, the desk next to you.
- **The first ~1.5 seconds** produce no verdict, and changing input device
  restarts that learning.

To see the numbers behind a verdict:

```bash
"/Applications/Am I Shouting.app/Contents/MacOS/AmIShouting" --probe 15
```

## Development

```bash
swift build && swift test    # 46 tests
make run                     # build, assemble, launch
make dmg                     # what a release ships
```

The detector takes its time from `LevelSample.time` rather than the wall clock,
so the tests drive it with a virtual clock and check the floor slew limits,
hysteresis and window behaviour deterministically.

## Releasing

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The [release workflow](.github/workflows/release.yml) tests, builds a universal
binary, packages a DMG with a SHA-256 checksum and publishes a GitHub release.
It signs and notarises instead — no workflow change — once these repository
secrets exist: `APPLE_CERTIFICATE` (a Developer ID Application `.p12`,
base64-encoded), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`
(app-specific), `APPLE_TEAM_ID`. All of them need a paid Apple Developer Program
membership; without one there is no way to avoid the first-launch warning.

## License

[MIT](LICENSE)

[releases]: https://github.com/kamil3di/am-i-shouting/releases/latest
