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
`xcode-27` runner and uploads `tabster-native-interaction`. Both local execution
and push-triggered runs default to the `boundaries` scenario. Manual workflow
dispatch offers a `scenario` choice. To run the original held-drag scenario locally:

```sh
TABSTER_INTERACTION_SCENARIO=held-drag bash tools/native-interaction/capture.sh
```

Only the selected XCTest method executes. Each test has a 75-second execution
limit, the observer stops after 60 seconds, and video recording stops after at
most 50 seconds. `scenario.txt` identifies the selected scenario in the artifact.

The scenarios use logical window coordinates on the 390-by-844 iPhone 14:

- `boundaries` (`testDragBoundaries`) performs four independent drags, each
  starting at `(195, 792)`. The endpoints, in order, are `(5, 792)`, `(385, 792)`,
  `(195, 692)`, and `(195, 832)`. Each gesture presses for 0.5 seconds, drags at
  velocity 80, holds for 1 second, releases, and waits 1 second. These samples
  expose horizontal edge resistance, vertical tracking, and release/cancellation
  behavior outside the tab bar; the probe does not prescribe the expected result.
- `held-drag` (`testHeldTabDrag`) slowly crosses the second tab center and holds
  at `x=238`, between the second and third centers. The reverse gesture stops
  at `x=152`, between the first and second centers, and holds before release.
  Compare touch x with the selection lens's presentation position during each
  hold and motion to determine whether UIKit snaps. The test makes no assumption
  about snapping behavior.

Artifacts under `target/native-interaction/artifacts` include:

- `native-drag.mp4`: up to 50 seconds of native display recording.
- `frames/`: PNG frames every 2 seconds from 2 through 48 seconds, where available,
  extracted with the system AVFoundation framework; `frames.json` records times.
- `interaction/interaction.jsonl`: accessibility flags, real touch positions,
  and tab-bar layer presentation geometry sampled at up to 60 Hz for 60 seconds.
- `interaction/NN-PHASE.json`: full layer/effect/filter snapshots, initially and
  0.25 seconds after each touch begins or ends, 1 second after a touch begins if
  still held, and once whenever a held pointer has stopped moving for 0.25 seconds.
  Filter keys combine the existing material probe's list and the filter's own
  reported `inputKeys`; data such as color matrices is encoded as base64.
- `released.png`, Xcode build/test logs, and the XCTest result bundle.

Layer IDs remain stable within a launch. `position`, `bounds`, `frame`,
`transform`, and `screenRect` come from presentation layers; `modelFrame` records
the model value for comparison. `screenRect` is in logical window points.
`displayTime` and touch `eventTime` use the monotonic system clock. `t` is relative
to observer startup. Private layer names are observed as data, not linked APIs.
