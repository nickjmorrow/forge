# Running the sync hub

The hub is just a Forge database plus an HTTP front door. Your phone, your Mac and the `forge` CLI that Claude uses on the server all sync through it, and the CLI on the server works on the hub's database directly.

Changes carry a logical timestamp; per thing (routine, workout, exercise…) the newest write wins, the same way on every device, so there is nothing to resolve by hand.

## 1. Build and install the CLI on the server

```bash
swift build --package-path CLI -c release
mkdir -p ~/.local/bin && ln -sf "$PWD/CLI/.build/release/forge" ~/.local/bin/forge
```

## 2. Tokens

One token per device (any random string). The file maps each token to a label:

```bash
mkdir -p ~/forge-hub
printf '{"%s": "iphone", "%s": "macbook"}\n' "$(uuidgen)" "$(uuidgen)" > ~/forge-hub/tokens.json
chmod 600 ~/forge-hub/tokens.json
cat ~/forge-hub/tokens.json     # copy a token into each device's Settings → Sync
```

## 3. Run it

```bash
forge sync-serve --db ~/forge-hub/forge.sqlite --tokens ~/forge-hub/tokens.json --port 8790
```

It listens on 127.0.0.1 only. Put Tailscale in front for HTTPS on your tailnet:

```bash
tailscale serve --bg --set-path /forge http://127.0.0.1:8790
```

To keep it running, copy `scripts/com.nicholai.forge-hub.plist` to `~/Library/LaunchAgents/`, edit the paths, and `launchctl load` it.

To reach it from a device where Tailscale DNS is off, use the hub's tailnet IP and pass the hub's name as the Host header, because Tailscale's front door routes by name: `forge sync-setup --url http://<tailnet ip>:<port> --token <token> --host-header <name>:<port>` (the apps' Settings → Sync has a matching optional field). The apps allow plain HTTP for this reason; the traffic is inside Tailscale's encrypted tunnel.

## 4. Connect each device

- **Apps:** Settings → Sync → hub address (`https://<hub>.<tailnet>.ts.net/forge`) and that device's token.
- **CLI:** `forge sync-setup --url https://<hub>.<tailnet>.ts.net/forge --token <token>`, then `forge sync`.

## Claude on the server

Point the MCP server at the hub's database so Claude edits the same data everyone syncs:

```bash
FORGE_DB=~/forge-hub/forge.sqlite python3 mcp/forge_mcp.py
```

Changes made there are numbered by the hub the next time anyone syncs, and then reach every device.
