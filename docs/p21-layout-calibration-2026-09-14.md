# P21 layout calibration run — 2026-09-14

> Historical prototype evidence. Disposable probe source and generated job files are preserved on the [`archive/p21-evidence-2026-09-14`](https://github.com/KalebCole/nelko-p21-cli/tree/archive/p21-evidence-2026-09-14) branch rather than on `main`.

**Issue:** #3
**Scope:** one tested P21 only, using native RFCOMM channel `1` on macOS.
**Result:** the rotation was later accepted as pixel-perfect during the fourteen-label run recorded on issue #4.

## Purpose

The earlier accepted raster used a `96 × 284` bitmap drawn directly in portrait coordinates. That is valid P21 bitmap packing, but it is a poor text-layout baseline: printable text has only 96 dots (about 12 mm at 203 dpi) across the short axis.

This run isolates **layout rotation** while holding all other known variables constant:

- bitmap payload: `96 × 284`, `12` bytes/row, `3,408` bytes;
- P21 sequence: `ESC ! o`, `SIZE 14.0 mm,40.0 mm`, `GAP 5.0 mm,0 mm`, `DIRECTION 1,1`, `DENSITY 15`, `CLS`, `BITMAP`, `PRINT 1`;
- one copy only;
- MSB-first pixels, where zero is black and one is white;
- native RFCOMM chunks no larger than negotiated MTU `666`.

The calibration drawing starts as a `284 × 96` landscape canvas and is rotated clockwise to the physical P21 `96 × 284` bitmap. It contains a filled square labeled `BLACK MARK = TOP LEFT`, a border, `P21 CALIBRATION`, and `ROTATED / ONE LABEL`. This makes orientation, clipping, and text readability observable on one inexpensive label.

The archived generator is `prototype-build-calibration-label.py`. Its offline output contract was checked before transmission:

```text
bytes: 3515
raster: 3408 bytes
header: ESC ! o + P21 TSPL-like command sequence
trailer: CRLF + PRINT 1 + CRLF
copies: 1
SHA-256: 5f3ae21ca2bd5014333d05825cb2748185a59b246f4c50f69723becffc062523
```

## Live trace

The printer was initially not ACL-connected. A readiness probe on native channel 1 sent `ESC ! ? CRLF` and received exactly one byte, `00`, which is the observed ready state. Closing that channel returns before macOS has always torn down its ACL link: an immediate second native open failed with `0xe00002bc`. After observing `blueutil --is-connected` return `0`, a fresh native open succeeded.

The one calibration job then produced:

```text
open: 0x00000000; MTU: 666
write: 3515 / 3515 bytes; result: 0x00000000
response: 000c011203000301121215280f0eed03 (16 bytes)
close: 0x00000000
```

The response matches the earlier accepted raster job exactly. Its semantic fields remain undecoded, so it is treated as an observed acknowledgement shape—not a definitive interpretation of the job outcome.

## Resulting protocol contract (provisional)

1. Bind all operations to this paired P21 address and RFCOMM channel 1; never use generic `blueutil --connect`.
2. A connection must begin only after no generic ACL connection is active.
3. Open one native RFCOMM session, query readiness (`ESC ! ? CRLF`), require the observed `00` byte, then write the complete single job in MTU-bounded chunks in **that same session**.
4. Require a nonempty protocol response after the job. A local write success is not enough.
5. Close the channel and wait for the device's ACL state to become disconnected before a subsequent RFCOMM attempt. A failed open sends no print bytes and may be retried only after that state transition.
6. Never automatically resend a job after a complete job write or an ambiguous response; it could duplicate a physical label.

## Subsequent evidence

The later fourteen-label run confirmed the clockwise layout and is recorded on [issue #4](https://github.com/KalebCole/nelko-p21-cli/issues/4#issuecomment-5672455769). Third-party reverse-engineered sources remain corroboration only. The current Wayfinder map separately tracks the software-observable runtime contract required for the production CLI.
