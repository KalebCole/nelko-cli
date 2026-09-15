# nelko-cli production contract

**Status:** implementation design for issue #7. This is a macOS-first, agent-safe CLI for exactly one supported target: a paired Nelko P21 at `FC:50:17:13:FF:8A`, native IOBluetooth RFCOMM channel `1`. It is not a general Bluetooth or label-printer CLI.

## Product boundary

Supported label media and renderer output are a 14 × 40 mm, `96 × 284` 1-bit raster: construct layouts at `284 × 96`, then rotate clockwise. The encoder owns the proven P21 job framing (`ESC ! o`, `SIZE`, `GAP`, `DIRECTION`, `DENSITY`, `CLS`, `BITMAP`, `PRINT`), MSB-first packing, and the single-copy rule.

Out of scope: another address, channel, non-P21 model, media geometry, generic `blueutil --connect`, serial-device fallback, persistent printer changes, firmware/reset/configuration commands, phone/cloud automation, and automatic retransmission of an ambiguously accepted job.

## Agent-facing command contract

Every command supports `--json` and `--no-input`. `--json` emits exactly one bounded JSON result to stdout and nothing else; diagnostics, prompts, and progress go to stderr. Without `--json`, stdout is a concise human rendering of the same result. Inputs never come from an interactive editor.

Target selection is exact: every hardware operation requires `--target FC:50:17:13:FF:8A`; any other or malformed address is rejected before transport creation. `--no-input` suppresses prompts. A physical operation with `--no-input` additionally requires `--confirm-print`; otherwise it fails with `confirmation_required` rather than guessing consent.

| CLI command | Shared operation | Safety | Result |
| --- | --- | --- | --- |
| `nelko status --target FC:50:17:13:FF:8A` | `p21.status` | read-only | battery, target, transport capability; no job bytes |
| `nelko preview --input LABEL.json --output preview.png` | `label.preview` | local-write | rendered preview metadata and output path |
| `nelko encode --input LABEL.json --output job.p21` | `p21.encode` | local-write | deterministic job metadata, hash, and output path |
| `nelko print --target FC:50:17:13:FF:8A --input LABEL.json` | `p21.print` | physical | one job result and acknowledgement metadata |
| `nelko print-batch --target FC:50:17:13:FF:8A --input batch.ndjson` | `p21.print_batch` | physical | ordered, bounded per-job results; stops at first unsafe failure |

`LABEL.json` is a versioned declarative label request, not raw printer language. `batch.ndjson` is one request per line in print order, with a maximum batch count and maximum input/job bytes defined in the operation catalog. `print`/`print-batch --dry-run` run validation, rendering, encoding, and return hashes/sizes; they do not open Bluetooth, probe the printer, or send bytes. `status --dry-run` performs no hardware I/O and reports the resolved target plus `dry_run: true`. `preview` and `encode` are already non-physical; `--dry-run` validates paths and reports planned outputs without writing them.

Physical operations prompt once for an explicit confirmation in interactive mode. They always print exactly one copy per request; batch confirmation identifies the requested job count. No implementation may add implicit retries after any job bytes have been completely written.

## Stable results, errors, and exits

All JSON responses have this envelope; fields only expand compatibly:

```json
{"ok":true,"operation":"p21.status","result":{"target":"FC:50:17:13:FF:8A"},"warnings":[]}
```

```json
{"ok":false,"operation":"p21.print","error":{"code":"readiness_timeout","message":"printer did not return ready state","retryable":true,"job_may_have_printed":false}}
```

Success metadata includes `target`, `dry_run`, and an operation-specific bounded result. A print result includes job SHA-256, byte count, negotiated MTU, and acknowledgement byte count/hex (capped at the catalog limit). Batch results include `requested`, `completed`, `stopped_at`, and at most the catalog maximum of per-job entries; excess detail is represented by counts and an error, never unbounded stdout.

Exit classes are stable: `0` success; `2` invalid invocation/input; `3` unsupported target/platform; `4` confirmation or policy refusal; `5` local render/encode/output failure; `6` transport/session failure before a job write; `7` readiness/battery gate failure before a job write; `8` acknowledgement failure or any ambiguous post-write state; `9` internal failure. Scripts must use JSON `error.code`, not message text.

Error codes are classified before implementation: `invalid_request`, `unsupported_target`, `confirmation_required`, `output_conflict`, `render_failed`, `encode_failed`, `transport_open_failed`, `transport_write_failed`, `battery_missing`, `battery_low`, `readiness_timeout`, `not_ready`, `ack_timeout`, `ack_invalid`, and `internal`. `job_may_have_printed` is required for all physical-operation errors and becomes `true` once a full job write completes. Exit `8` is never auto-retried.

## Proven physical lifecycle

`p21.print_batch` opens one native RFCOMM session for the batch; `p21.print` uses the same lifecycle for one item. It must:

1. reject generic ACL connection use and resolve only the fixed paired target/channel;
2. open with `IOBluetoothDevice openRFCOMMChannelSync:withChannelID:delegate:`, require success, an open channel, and a positive MTU;
3. obtain and parse the battery reply before every job; missing/unacceptable battery stops before that job;
4. poll `ESC ! ?\r\n` before every job until the observed ready byte `00` or a bounded timeout; any other/missing reply stops;
5. write the already encoded single-copy job in chunks no larger than the negotiated MTU (666 observed), retaining asynchronous response bytes through the delegate/run loop;
6. require the observed 16-byte post-job acknowledgement before advancing. Its fields are not yet decoded, so acceptance means exactly the known 16-byte shape, not merely a nonempty response;
7. on any gate failure, close the session and return a structured failure without sending the next job. Never resend the failed/ambiguous job automatically.

The batch lifecycle is grounded in issue #4 acceptance evidence: 14 labels printed after a power reset, including 11 in one channel-1 session with battery/readiness/acknowledgement gates for each 3,515-byte job.

## Architecture and typed seams

The executable is a thin argv adapter over the operation catalog; it may not contain transport protocol logic or renderer layout logic. Future MCP tools call the same catalog with typed requests and receive the same typed result/error envelope—never synthesize argv. MCP is not an initial delivery requirement: the P21 has a narrow operation set, but the seam is justified for agent callers and prevents a duplicated policy layer.

```text
CLI argv / future MCP
        -> OperationCatalog (validation, safety, bounds, confirmation policy)
        -> Operations (status, preview, encode, print, print_batch)
        -> Renderer + Encoder             -> Transport
        -> artifacts/results                -> native IOBluetooth adapter
```

Implementation interfaces (language-neutral names; concrete types must preserve these fields):

```text
Renderer.render(LabelRequest) -> Raster96x284
Encoder.encode(Raster96x284) -> EncodedJob { bytes, sha256, byte_count }
Transport.open(Target) -> Session { mtu, query(bytes, timeout), write(bytes), responses(), close() }
P21Protocol.preflight(Session) -> BatteryStatus
P21Protocol.await_ready(Session, deadline) -> Ready
P21Protocol.await_ack(Session, deadline) -> JobAck
OperationCatalog.invoke(OperationRequest, InvocationPolicy) -> OperationResult | OperationError
```

`Renderer` and `Encoder` have no Bluetooth dependency. `Transport` neither interprets P21 commands nor chooses retries. `P21Protocol` owns byte-level gates and maps raw reply evidence to typed states. Operations own ordering, stop behavior, result bounds, and `job_may_have_printed`. The native adapter owns IOBluetooth delegate/run-loop plumbing only.

## Repository artifacts and mergeable work

- `docs/`: this contract and physical evidence; no executable ownership.
- `nelko_p21/contract.py` (or equivalent): typed requests/results/errors, catalog, safety/exit policy.
- `nelko_p21/render.py`: declarative-label renderer and deterministic raster/P21 encoder.
- `native/`: Objective-C native adapter executable/library only; no argv policy.
- `nelko_p21/__main__.py`: CLI adapter only.
- `tests/`: fixture-only tests for catalog, CLI JSON, renderer, encoder, and fake transport; no hardware.
- `artifacts/`: generated previews/jobs and immutable live acceptance captures; never required as source inputs.

Independently mergeable tickets: (1) contract/catalog plus JSON and exit-class tests; (2) renderer/encoder golden fixtures and preview/encode commands; (3) native transport adapter and fake-transport conformance tests; (4) print orchestration with gate/stop tests; (5) opt-in physical acceptance test that records target, job hash, MTU, battery/readiness/ack evidence and requires a human observation. A future MCP ticket wraps the catalog only after the CLI contract is stable.
