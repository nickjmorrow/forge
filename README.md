# Forge

A workout tracker for iPhone and Mac that replaces Hevy: exercise library, routines, workout logging with a rest timer, history and progress, Apple Health, and an agent interface so an AI can do anything the app can (including deleting your custom exercises).

- **iPhone** is for logging: start from a routine, see what you did last time, tick sets, rest timer with a lock-screen Live Activity, finish.
- **Mac** is for reviewing and planning, not logging: dashboard (week at a glance, training calendar, records, sleep vs training), exercise charts, routines laid out whole and edited in place (drag to reorder routines and exercises), library and past workouts.
- **Claude** works through the `forge` command line and an MCP server, on the same data. Every change Claude makes is labelled and undoes in one step.
- **Sync** keeps phone, Mac and a server copy in step (see [docs/hub.md](docs/hub.md)).

## Layout

| | |
|---|---|
| `Core/` | `ForgeCore` (Swift 6, SQLite via GRDB): data model, logged ops with inverses and one-step undo, stats, Hevy import, recovery data, sync client and hub logic |
| `UI/` | `ForgeUI`: the app model, workout session logic, rest timer, Apple Health bridge, and all SwiftUI screens shared by iPhone and Mac |
| `App/` | XcodeGen project: iOS app (with the rest-timer Live Activity extension) and macOS app |
| `CLI/` | `forge`: JSON command line over Core, plus `sync-serve` (the hub) |
| `mcp/` | MCP server (stdio) that wraps the CLI for Claude |

## Build and test

```bash
swift test --package-path Core
swift test --package-path UI
swift test --package-path CLI
swift build --package-path CLI -c release       # CLI/.build/release/forge
python3 -m unittest discover -s mcp             # needs the release CLI

scripts/build-mac.sh Release                    # needs XcodeGen: brew install xcodegen
```

For an iPhone build, copy `.env.example` to `.env`, set `DEVELOPMENT_TEAM`, then `scripts/generate-project.sh` and run the `ForgeiOS` scheme from Xcode. Apple Health needs a properly signed build (the HealthKit entitlement), so it only works on a device or a signed simulator build.

## Using it with Claude

```bash
claude mcp add forge -- python3 <repo>/mcp/forge_mcp.py
```

Then ask for things like "remove every Acme exercise from my routines", "reorder my routines", "suggest a pull day from what I've been doing", or "how's my bench trending?". See [mcp/README.md](mcp/README.md).

## The command line

The database defaults to `~/Library/Application Support/Forge/forge.sqlite` (the file the Mac app opens; override with `--db` or `$FORGE_DB`). Everything prints JSON; errors are `{"error": "..."}` on stderr with exit code 1; `--author` defaults to `claude`.

```bash
forge import-hevy                                   # HEVY_API_KEY, or --from-dir with templates/routines/workouts JSON
forge exercise list --match acme
forge routine remove-exercise Acme --preview     # see the effect first
forge routine remove-exercise Acme               # one undoable change
forge exercise delete <id> --merge-into <other id>  # history moves; --force removes it everywhere
forge routine put --json '{"title":"Push","exercises":[{"exercise":"Bench Press (Barbell)","sets":[{"weightLb":135,"reps":8}]}]}'
forge workout put --json '{"title":"Legs","startedAt":"2026-10-19T17:00:00Z","exercises":[…]}'
forge stats prs <exercise id>
forge sql "select name, count(*) from exercises group by 1"   # read-only; `forge schema` lists the tables
forge recovery put --json '[{"date":"2026-10-20","source":"eight_sleep","sleepSeconds":27000,"sleepScore":75}]'
forge undo                                          # reverses the latest change by --author
forge sync-setup --url https://… --token …  &&  forge sync
```

Deleting an exercise that appears in routines or workouts is refused unless you pass `--merge-into` or `--force`, so a delete can't silently wipe history.
