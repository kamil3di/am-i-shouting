# Am I Shouting?

A small level meter that lives in the macOS menu bar and answers exactly that
question. It continuously learns the room's noise floor, compares your voice
against it, and tells you by colour whether you are shouting.

```
[▬▬▬▬▬▭|▭]   green = normal · yellow = loud · red = shouting
```

No Dock icon (`LSUIElement`), no window. Audio is never recorded or sent
anywhere; it exists only as a running level calculation in memory.

The UI ships in **English** and can be switched to **Türkçe** from the popover
at any time — the choice is remembered.

## How it works

A single microphone cannot physically separate "the room" from "your voice" —
it hears both at once. So this app measures something it actually can:
**how many dB above the room's noise floor you are.**

1. **Noise floor** — the 10th percentile of the last 12 seconds. The gaps
   between words reveal what the room itself sounds like, and the floor is
   learned from those. It may only rise at ~3 dB/s, so even sustained shouting
   never becomes "ambient"; it falls quickly (20 dB/s), because a room going
   quiet is real and immediate.
2. **Your current level** — the 80th percentile of the last 0.8 seconds. Not the
   peak: a single door slam or keyboard click occupies too few slices to reach
   the 80th percentile, while real speech reaches it easily.
3. **Excess** = level − floor. The thresholds sit on top of that excess:
   normal (default +22 dB) → loud (+5 dB) → shouting (+11 dB).
4. **Hysteresis** — escalating is fast (0.15 s) and calming down is slow
   (0.9 s), so the colour does not flicker between words.

The result: a level that counts as shouting in a silent office is an ordinary
speaking voice in a busy café. The bar moves with the room.

## Install

```bash
make app && open "dist/Am I Shouting.app"
```

`make app` compiles, assembles `dist/Am I Shouting.app` and signs it ad-hoc. The
signature uses a stable identifier, so macOS remembers the microphone grant
across rebuilds. The first launch asks for microphone access.

For a universal Intel + Apple Silicon binary, use `make universal`.

## Using it

Click the bar in the menu bar to open the panel:

- **Ambient noise / your level / above ambient / shout threshold** — live dB
  readings.
- **Measure my normal voice** — speak normally for 5 seconds; the thresholds are
  rebuilt around your own voice and saved. This calibration is the only thing
  that knows your microphone, your voice and how far you sit from it, so it is
  by far the most useful setting.
- **Sensitivity** — −8…+8 dB. Sliding right lowers the thresholds (flags you
  earlier).
- **Language** — English / Türkçe, applied immediately.
- **Pause** — releases the microphone.

Settings are stored in `UserDefaults`.

## Diagnostic mode

To see what is being measured without watching the menu bar:

```bash
"./dist/Am I Shouting.app/Contents/MacOS/AmIShouting" --probe 15
```

It prints a few lines per second of input / floor / voice / excess / state. This
is the quickest way to tune thresholds for your own room, or to answer "why did
it just go red?".

## Known limits

- **AirPods and similar Bluetooth headsets** apply their own noise and echo
  cancellation. Audio the Mac plays itself largely never reaches the microphone
  (so testing by playing a sound through the speakers does not work), and the
  noise floor looks quieter than the real room. Calibration compensates.
- **The first ~1.5 seconds** produce no verdict; the state stays "quiet" until
  the floor has been learned. Changing the input device (plugging in a headset)
  rebuilds the tap and restarts that learning.
- **A silent input is rejected rather than believed.** A fresh or muted stream
  delivers exact zeros (−100 dBFS); treating that as "a very quiet room" would
  peg the floor at digital silence and make the next ordinary word look like a
  40 dB scream. The panel says "No signal" instead.
- **There is no speech recognition.** Any sustained sound loud enough counts as
  speech: a radiator, an air conditioner, the desk next to you.
- **dBFS is not an absolute measure of loudness.** It depends on microphone
  gain, which is exactly why everything here is measured *relative* to the room.

## Development

```bash
swift build          # compile
swift test           # 46 tests
make run             # build, assemble, launch
make clean
```

The detector takes its time from `LevelSample.time` rather than the wall clock,
so the tests drive it with a virtual clock at 20 frames per second and verify
the floor slew limits, hysteresis and window behaviour deterministically. The
menu bar image is verified by reading pixels back out of it, and the popover is
laid out in both languages as a smoke test.

| File | Responsibility |
| --- | --- |
| `AudioMonitor.swift` | `AVAudioEngine` tap; slices buffers into 40 ms chunks and reports RMS / peak dBFS |
| `ShoutDetector.swift` | Noise floor, excess, thresholds, hysteresis, calibration |
| `MeterModel.swift` | Audio + detector + persisted settings, as an `ObservableObject` |
| `StatusItemController.swift` | `NSStatusItem`, the live bar, the popover |
| `LevelBarImage.swift` | Drawing of the menu bar image |
| `DetailView.swift` | SwiftUI panel |
| `Localization.swift` | The app name and every user-facing string, in both languages |
| `Probe.swift` | `--probe` diagnostic mode |
