# nelko-cli

A macOS-first, agent-safe CLI for exactly one supported Nelko P21 Bluetooth label printer. It is deliberately not a generic Bluetooth or printer-management tool.

The implementation contract, operation catalog, JSON/error behavior, physical safety gates, repository boundaries, and future MCP seam are in [docs/cli-contract.md](docs/cli-contract.md). Live transport evidence and the accepted physical batch evidence are preserved in [docs/live-transport-investigation.md](docs/live-transport-investigation.md) and [issue #4](https://github.com/KalebCole/nelko-cli/issues/4).
