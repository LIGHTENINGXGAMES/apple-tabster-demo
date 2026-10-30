# Native tab interaction probe

This simulator-only probe records actual UIKit tab interaction. It keeps the
Tabster guest source and binary unchanged. XCTest injects real press, drag,
hold, and release events; the observer never changes selection or layer values.

Run on a Mac with the iOS 27 SDK and iOS 27.0 simulator runtime:

```sh
bash scripts/build-tabster.sh iphonesimulator
bash tools/native-interaction/capture.sh
```

The isolated `Native tab interaction` workflow runs the same commands on the
`xcode-27` runner and uploads `tabster-native-interaction`.

Artifacts under `target/native-interaction/artifacts` include:

- `native-drag.mp4`: up to 16 seconds of native display recording.
- `frames/`: PNG frames at 2, 4, 6, 8, 10, 12, and 14 seconds, where available,
  extracted with the system AVFoundation framework; `frames.json` records times.
- `interaction/interaction.jsonl`: accessibility flags, real touch positions,
  and tab-bar layer presentation geometry sampled at up to 60 Hz for 20 seconds.
- `interaction/NN-PHASE.json`: full layer/effect/filter snapshots, initially and
  0.25 seconds after each touch begins or ends. Filter keys reuse the existing
  material probe's list; data such as color matrices is encoded as base64.
- `released.png`, Xcode build/test logs, and the XCTest result bundle.

The first gesture slowly crosses the second tab center and holds at x=238,
between the second and third centers. The reverse gesture stops at x=152,
between the first and second centers, and holds before release. Compare touch x
with the selection lens's presentation position during each hold and motion.
Determine snapping behavior from those samples;
the test intentionally makes no assumption about whether UIKit snaps.

Layer IDs remain stable within a launch. `position`, `bounds`, `frame`,
`transform`, and `screenRect` come from presentation layers; `modelFrame` records
the model value for comparison. `screenRect` is in logical window points.
`displayTime` and touch `eventTime` use the monotonic system clock. `t` is relative
to observer startup. Private layer names are observed as data, not linked APIs.
