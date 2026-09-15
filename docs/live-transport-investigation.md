# Live transport investigation: Nelko P21 on macOS

> Historical prototype evidence. Disposable probe source and generated job files are preserved on the [`archive/p21-evidence-2026-09-14`](https://github.com/KalebCole/nelko-p21-cli/tree/archive/p21-evidence-2026-09-14) branch rather than on `main`.

**Issue:** #2  
**Date:** 2026-09-14  
**State:** transport and protocol acknowledgement were proven in this run; later batch evidence is recorded on issue #4.

## Scope and safety

The experiments were constrained to the tested paired P21, RFCOMM channel 1, and the documented read-only `BATTERY?` query before one single-copy, visibly marked test job. No firmware, factory-reset, configuration, beep, or mobile-app command was used. `DENSITY 15` and `DIRECTION 1,1` appear only in the submitted print job and are not claimed to be persistent printer settings.

## Layered evidence

| Layer | Result | Evidence |
| --- | --- | --- |
| Pairing | Proven | macOS reports P21 paired at the expected address. |
| ACL / service discovery | Proven but insufficient | `blueutil --connect` and serial-node access caused SDP/ACL activity only. |
| Serial port endpoint | Present but not a usable client transport | `/dev/cu.P21` exists. A direct 115200 serial `BATTERY?\r\n` write returned no bytes in 2.0 seconds and produced no RFCOMM connection in the Bluetooth daemon log. |
| SPP/RFCOMM service | Proven | SDP found `SerialPort`; macOS persistent-port data records RFCOMM channel 1. |
| RFCOMM session | Proven | Native `IOBluetoothDevice openRFCOMMChannelSync:... channelID:1` returned `0x00000000`, channel open, MTU 666, and Bluetooth daemon logged RFCOMM connection. |
| Read-only command acknowledgement | Proven | `BATTERY?\r\n` was sent with `writeSync`; the printer returned `BATTERY 0x75 0x00\r\n` (hex `424154544552592075000d0a`). |
| Test job accepted at transport/protocol boundary | Proven, not physical proof | The 3,515-byte job was chunked at the negotiated MTU and every write returned `0x00000000`; the printer returned 16 bytes: `000c011203000301121215280f0eed03`. Its semantic meaning is not yet decoded. |
| Physical label printed | **Unconfirmed** | Requires Kaleb to inspect the printer/label. |

## Root cause hypothesis, tested

The old direct serial approach mistook the existence of `/dev/cu.P21` for an open printer session. On this Mac, opening that path did not establish an RFCOMM service connection; its successful write was only local kernel acceptance. Opening channel 1 through the native IOBluetooth framework does establish RFCOMM and produces a printer response. This is supported by the contrast between the two probes above.

## Exact successful session contract so far

1. Resolve only the tested paired P21 and only RFCOMM channel `1`.
2. Open it using `IOBluetoothDevice openRFCOMMChannelSync:withChannelID:delegate:`.
3. Verify `kIOReturnSuccess`, a non-null open channel, and its MTU before sending bytes.
4. Send commands with `IOBluetoothRFCOMMChannel writeSync:length:` in chunks no larger than the reported MTU (666 in this session).
5. Hold the delegate/run loop to collect asynchronous response bytes; a completed local write alone is not job acceptance.
6. Close the RFCOMM channel after the bounded response wait.

## Submitted physical test label

The job was exactly one 14.0 mm × 40.0 mm raster label, 3,515 bytes, SHA-256 `ac2e5062175da152e73636b298dbe3bd91303a49c9bbf1a7bf32fded2696ef01`.

It begins with:

```text
ESC ! o CRLF
SIZE 14.0 mm,40.0 mm CRLF
GAP 5.0 mm,0 mm CRLF
DIRECTION 1,1 CRLF
DENSITY 15 CRLF
CLS CRLF
BITMAP 0,0,12,284,1,<3408 bytes> CRLF
PRINT 1 CRLF
```

The rendered label says `P21 LIVE TEST`, `RFCOMM OK`, `2026-09-14`, and `ONE LABEL` inside a border. It was sent once only.

## Subsequent evidence

This document records the transport boundary observed during the initial probe. The later fourteen-label run and its acceptance evidence are recorded on [issue #4](https://github.com/KalebCole/nelko-p21-cli/issues/4#issuecomment-5672455769). Product success semantics are intentionally not inferred from this historical probe; the current Wayfinder map tracks that decision separately.
