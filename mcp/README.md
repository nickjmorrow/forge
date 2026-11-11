# forge-mcp

MCP server for Claude (stdio). Wraps the `forge` CLI, so every tool behaves exactly like the command line, and everything Claude writes is recorded as author `claude` (undo with `undo_claude`).

Needs `forge` on PATH or at `~/.local/bin/forge`: `swift build --package-path CLI -c release`, then link `CLI/.build/release/forge` to `~/.local/bin/forge` (or set `FORGE_BIN`). The database defaults to `~/Library/Application Support/Forge/forge.sqlite`, the same file the Mac app opens (override with `FORGE_DB`).

Add to Claude Code: `claude mcp add forge -- python3 <repo>/mcp/forge_mcp.py`

Tests (need the release CLI built): `python3 -m unittest discover -s mcp`
