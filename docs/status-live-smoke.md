# Status smoke check

Build with `swift build`, then run this **read-only** direct RFCOMM check manually against the paired P21:

```sh
.build/debug/nelko status --no-input
```

For agentic callers, request a stable DTO instead. Progress goes only to stderr; stdout is JSON:

```sh
.build/debug/nelko status --no-input --json
```

Do not run this as CI: it opens the paired printer directly at `FC:50:17:13:FF:8A` on RFCOMM channel 1. It does not use generic Bluetooth ACL or `/dev/cu.P21`, and it sends only `BATTERY?` plus the readiness query. A `connection_conflict` result means another Bluetooth client may be holding the printer; disconnect it before retrying.
