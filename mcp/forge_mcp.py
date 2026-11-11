#!/usr/bin/env python3
"""Forge MCP server (stdio). A thin wrapper: every tool runs the `forge` CLI, so the CLI and Claude behave identically.

Environment: FORGE_DB (database file, default ~/Library/Application Support/Forge/forge.sqlite), FORGE_BIN (path to forge,
default `forge` on PATH or ~/.local/bin/forge). Everything Claude writes is recorded as author `claude`, so undo_claude can revert it.
"""
import json
import os
import shutil
import subprocess
import sys

PROTOCOL = "2025-06-18"
FORGE = os.environ.get("FORGE_BIN") or shutil.which("forge") or os.path.expanduser("~/.local/bin/forge")

INSTRUCTIONS = (
    "Forge is the user's workout tracker (it replaces Hevy): exercise library, routines, logged workouts, bodyweight. "
    "Weights are stored in kg; give weightLb in inputs when the user speaks in pounds, and tell them pounds. "
    "Anything the app can do you can do, including deleting custom exercises. Everything you write is logged as Claude and undone with undo_claude. "
    "Before a bulk change (removing an exercise from every routine, merging exercises) use preview_remove_exercise or list the matches first and tell the user what will change. "
    "Deleting an exercise that has history needs merge_into (history moves to the other exercise) or force (history is removed): ask which. "
    "For progress questions use exercise_prs, exercise_history, weekly_sets, or sql (call schema first)."
)


def S(desc, **props):
    return ({"type": "object",
             "properties": {k: {"type": v[0], "description": v[1], **({"items": {"type": "string"}} if v[0] == "array" else {})} for k, v in props.items()},
             "required": [k for k, v in props.items() if len(v) < 3], "additionalProperties": False}, desc)


def opt(args, flag, value):
    # "--flag=value" so a value that starts with "-" is not mistaken for another option
    return args + [f"{flag}={value}"] if value not in (None, "") else args


def put_json(base, a, key):
    value = a[key]
    return base + ["--json", value if isinstance(value, str) else json.dumps(value)]


ROUTINE_SHAPE = ("A routine object: {title, id?, folder?, position?, exercises: [{exercise: 'Exact Name' (or exerciseID), notes?, restSeconds?, supersetID?, "
                 "sets: [{weightLb or weightKg, reps, type?: normal|warmup|failure|drop, durationSeconds?, distanceMeters?, rpe?}]}]}. "
                 "With an existing id it replaces that routine.")
WORKOUT_SHAPE = ("A workout object: {title, startedAt (ISO-8601, required), endedAt?, notes?, routineID?, id?, exercises: same shape as routines}. "
                 "Sets default to completed. With an existing id it replaces that workout.")
EXERCISE_SHAPE = ("An exercise object: {name, equipment?, primaryMuscle?, secondaryMuscles?: [..], tracking?: weightReps|repsOnly|weightedBodyweight|assistedBodyweight|duration|weightDuration|distance|distanceDuration, id?}. "
                  "With an existing id only the given fields change.")

# name -> (schema, description, argv builder). Builders return the arguments after `forge`.
TOOLS = {
    "list_exercises": (*S("The exercise library, optionally filtered by text in the name, equipment or muscles.", match=("string", "Text to match", "opt")),
                       lambda a: opt(["exercise", "list"], "--match", a.get("match"))),
    "get_exercise": (*S("One exercise with how many workouts and routines use it, and its personal records.", id=("string", "Exercise id")),
                     lambda a: ["exercise", "show", a["id"]]),
    "put_exercise": (*S("Create an exercise or update fields of one (rename, change muscle, equipment, tracking).", exercise=("object", EXERCISE_SHAPE)),
                     lambda a: put_json(["exercise", "put"], a, "exercise")),
    "delete_exercise": (*S("Delete an exercise. If it appears in routines or workouts you must give merge_into (history moves to that exercise) or force=true (removed everywhere); otherwise it is refused.",
                           id=("string", "Exercise id"), merge_into=("string", "Exercise id to receive its history", "opt"), force=("boolean", "Remove it from every routine and workout", "opt")),
                        lambda a: opt(["exercise", "delete", a["id"]], "--merge-into", a.get("merge_into")) + (["--force"] if a.get("force") else [])),
    "list_routines": (*S("All routines in order, with their exercises and planned sets."), lambda a: ["routine", "list"]),
    "get_routine": (*S("One routine.", id=("string", "Routine id")), lambda a: ["routine", "show", a["id"]]),
    "put_routine": (*S("Create a routine or replace one (use it to rewrite sets, reorder exercises or build a suggested routine once the user agrees).", routine=("object", ROUTINE_SHAPE)),
                    lambda a: put_json(["routine", "put"], a, "routine")),
    "delete_routine": (*S("Delete a routine. Past workouts from it are kept.", id=("string", "Routine id")), lambda a: ["routine", "delete", a["id"]]),
    "reorder_routines": (*S("Put the routines in a new order. Give every routine id exactly once.", ids=("array", "All routine ids in the new order")),
                         lambda a: ["routine", "reorder", "--"] + list(a["ids"])),
    "preview_remove_exercise": (*S("Which routines would lose which exercises if every exercise whose name contains any of these texts were removed. Changes nothing.",
                                   names=("array", "Name fragments, case-insensitive (e.g. ['Acme'])")),
                                lambda a: ["routine", "remove-exercise", "--preview", "--"] + list(a["names"])),
    "remove_exercise_from_routines": (*S("Remove every exercise whose name contains any of these texts from ALL routines in one undoable change. Workout history is untouched. Preview first.",
                                         names=("array", "Name fragments, case-insensitive")),
                                      lambda a: ["routine", "remove-exercise", "--"] + list(a["names"])),
    "list_workouts": (*S("Recent workouts, newest first, with exercise names and sets.", limit=("integer", "How many (default 20)", "opt")),
                      lambda a: opt(["workout", "list"], "--limit", a.get("limit"))),
    "get_workout": (*S("One workout.", id=("string", "Workout id")), lambda a: ["workout", "show", a["id"]]),
    "put_workout": (*S("Log a past workout, or replace/fix one by id.", workout=("object", WORKOUT_SHAPE)), lambda a: put_json(["workout", "put"], a, "workout")),
    "delete_workout": (*S("Delete a workout.", id=("string", "Workout id")), lambda a: ["workout", "delete", a["id"]]),
    "exercise_prs": (*S("Personal records for an exercise: heaviest weight, best estimated 1-rep max, best set volume (kg).", id=("string", "Exercise id")),
                     lambda a: ["stats", "prs", a["id"]]),
    "exercise_history": (*S("Completed sets of an exercise per workout, newest first.", id=("string", "Exercise id"), limit=("integer", "Sessions (default 20)", "opt")),
                         lambda a: opt(["stats", "history", a["id"]], "--limit", a.get("limit"))),
    "weekly_sets": (*S("Completed working sets per muscle per week (weeks start Monday).", weeks=("integer", "How many weeks back (default 8)", "opt")),
                    lambda a: opt(["stats", "weekly-sets"], "--weeks", a.get("weeks"))),
    "set_bodyweight": (*S("Record bodyweight for a day.", date=("string", "YYYY-MM-DD"), lb=("number", "Pounds", "opt"), kg=("number", "Kilograms", "opt")),
                       lambda a: opt(opt(["bodyweight", "set", a["date"]], "--lb", a.get("lb")), "--kg", a.get("kg"))),
    "list_bodyweight": (*S("Bodyweight entries, newest first.", limit=("integer", "How many (default 90)", "opt")), lambda a: opt(["bodyweight", "list"], "--limit", a.get("limit"))),
    "put_recovery": (*S("Save sleep/recovery rows (one per morning per source). Use it to copy Eight Sleep nights (from the eight_sleep tools) or Apple Health numbers into Forge. Only the given fields change.",
                        entries=("array", "Rows: {date: 'YYYY-MM-DD' (the morning), source: 'eight_sleep' | 'apple_health', sleepSeconds?, sleepScore?, hrvMs?, restingHR?}")),
                     lambda a: ["recovery", "put", "--json", json.dumps(a["entries"])]),
    "list_recovery": (*S("Sleep and recovery rows, newest first.", from_date=("string", "First day YYYY-MM-DD", "opt"), to_date=("string", "Last day YYYY-MM-DD", "opt")),
                      lambda a: opt(opt(["recovery", "list"], "--from", a.get("from_date")), "--to", a.get("to_date"))),
    "schema": (*S("The database tables and columns, for writing sql queries. Weights are kg, times are milliseconds since epoch."), lambda a: ["schema"]),
    "sql": (*S("Read-only SQL (one SELECT) for progress questions nobody planned for. Call schema first.", query=("string", "A SELECT statement"), limit=("integer", "Max rows (default 500)", "opt")),
            lambda a: opt(["sql"], "--limit", a.get("limit")) + ["--", a["query"]]),
    "changes": (*S("The change log: what was changed, by whom, and whether it was undone or skipped.", by=("string", "me, claude or importer", "opt"), since=("integer", "Milliseconds since epoch", "opt")),
                lambda a: opt(opt(["changes"], "--by", a.get("by")), "--since", a.get("since"))),
}


READ_ONLY = {"list_exercises", "get_exercise", "list_routines", "get_routine", "list_workouts", "get_workout", "exercise_prs", "exercise_history",
             "weekly_sets", "list_bodyweight", "list_recovery", "schema", "sql", "changes", "preview_remove_exercise"}
AUTOSYNC = os.environ.get("FORGE_AUTOSYNC", "1") != "0"


def sync_quietly():
    """Keep this copy in step with the sync hub when sync is set up (a no-op, quickly, when it isn't, or when the hub is unreachable)."""
    if not AUTOSYNC:
        return
    try:
        subprocess.run([FORGE, "sync"], capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        pass


def run_forge(args):
    argv = [FORGE] + args
    if "--author" not in argv:
        i = argv.index("--") if "--" in argv else len(argv)
        argv[i:i] = ["--author", "claude"]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"could not run forge: {e}", True
    out = (p.stdout or "").strip()
    if p.returncode != 0:
        return (p.stderr.strip() or out or f"forge exited {p.returncode}"), True
    return out or "ok", False


def run_tool(name, args):
    sync_quietly()                      # pick up what the phone and Mac did since the last call
    text, err = _run_tool(name, args)
    if name not in READ_ONLY and not err:
        sync_quietly()                  # and send what this call changed
    return text, err


def _run_tool(name, args):
    if name == "undo_claude":
        results = []
        for _ in range(max(1, int(args.get("last") or 1))):
            text, err = run_forge(["undo"])
            if err:
                return text, True
            results.append(json.loads(text))
            if results[-1].get("undone", 0) == 0 and not results[-1].get("skipped"):
                break
        return json.dumps(results if len(results) > 1 else results[0], indent=1), False
    if name not in TOOLS:
        return f"unknown tool: {name}", True
    try:
        return run_forge(TOOLS[name][2](args))
    except KeyError as e:
        return f"missing argument: {e}", True


TOOLS["put_recovery"][0]["properties"]["entries"]["items"] = {"type": "object"}
TOOL_LIST = [{"name": n, "description": d, "inputSchema": s} for n, (s, d, _) in TOOLS.items()]
TOOL_LIST.append({"name": "undo_claude", "description": "Undo Claude's latest change(s) (a bulk edit is one change). A change is skipped, not forced, if the user edited the same thing afterwards.",
                  "inputSchema": S("", last=("integer", "How many changes (default 1)", "opt"))[0]})


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:  # notification
        return None

    def ok(result): return {"jsonrpc": "2.0", "id": mid, "result": result}

    def err(code, text): return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": text}}

    if method == "initialize":
        return ok({"protocolVersion": PROTOCOL, "capabilities": {"tools": {}}, "serverInfo": {"name": "forge", "version": "1.0"}, "instructions": INSTRUCTIONS})
    if method == "ping":
        return ok({})
    if method == "tools/list":
        return ok({"tools": TOOL_LIST})
    if method == "tools/call":
        params = msg.get("params") or {}
        text, is_err = run_tool(params.get("name", ""), params.get("arguments") or {})
        return ok({"content": [{"type": "text", "text": text}], "isError": is_err})
    return err(-32601, f"method not found: {method}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        try:
            reply = handle(msg)
        except Exception as e:  # never die on one bad request
            reply = {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32603, "message": str(e)}}
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
