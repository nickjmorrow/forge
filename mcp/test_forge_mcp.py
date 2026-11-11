import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FORGE_BIN = os.environ.get("FORGE_BIN") or os.path.join(HERE, "..", "CLI", ".build", "release", "forge")


@unittest.skipUnless(os.path.exists(FORGE_BIN), "build the CLI first: swift build --package-path CLI -c release")
class McpTests(unittest.TestCase):
    def setUp(self):
        self.db = os.path.join(tempfile.mkdtemp(), "forge.sqlite")
        env = dict(os.environ, FORGE_DB=self.db, FORGE_BIN=FORGE_BIN)
        self.p = subprocess.Popen([sys.executable, os.path.join(HERE, "forge_mcp.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
        self.n = 0

    def tearDown(self):
        self.p.stdin.close()
        self.p.wait()
        self.p.stdout.close()

    def call(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def tool(self, name, **args):
        r = self.call("tools/call", {"name": name, "arguments": args})["result"]
        return r["content"][0]["text"], r["isError"]

    def ok(self, name, **args):
        text, err = self.tool(name, **args)
        self.assertFalse(err, text)
        return json.loads(text)

    def seed(self):
        bench = self.ok("put_exercise", exercise={"name": "Bench Press (Barbell)", "primaryMuscle": "chest"})["id"]
        acme = self.ok("put_exercise", exercise={"name": "Pec Deck (Machine, Acme)", "primaryMuscle": "chest"})["id"]
        routine = self.ok("put_routine", routine={"title": "Chest", "exercises": [
            {"exercise": "Bench Press (Barbell)", "restSeconds": 120, "sets": [{"weightLb": 200, "reps": 5}]},
            {"exercise": "Pec Deck (Machine, Acme)", "sets": [{"weightLb": 100, "reps": 12}]}]})["id"]
        return bench, acme, routine

    def test_handshake_and_tool_list(self):
        r = self.call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}})
        self.assertEqual(r["result"]["serverInfo"]["name"], "forge")
        self.assertIn("undo_claude", r["result"]["instructions"])
        tools = self.call("tools/list")["result"]["tools"]
        names = {t["name"] for t in tools}
        self.assertTrue({"put_routine", "put_workout", "delete_exercise", "remove_exercise_from_routines", "sql", "schema", "undo_claude", "exercise_prs"} <= names)
        for t in tools:
            self.assertEqual(t["inputSchema"]["type"], "object")
            self.assertTrue(t["description"])

    def test_remove_acme_flow_is_previewed_applied_and_undone(self):
        _, _, routine = self.seed()
        preview = self.ok("preview_remove_exercise", names=["Acme"])
        self.assertFalse(preview["applied"])
        self.assertEqual(preview["routines"][0]["removedExercises"], ["Pec Deck (Machine, Acme)"])
        self.assertEqual(len(self.ok("get_routine", id=routine)["exercises"]), 2)
        applied = self.ok("remove_exercise_from_routines", names=["Acme"])
        self.assertTrue(applied["applied"])
        self.assertEqual(len(self.ok("get_routine", id=routine)["exercises"]), 1)
        self.ok("undo_claude")
        self.assertEqual(len(self.ok("get_routine", id=routine)["exercises"]), 2)

    def test_deleting_an_exercise_with_history_needs_a_choice(self):
        bench, acme, _ = self.seed()
        self.ok("put_workout", workout={"title": "Chest", "startedAt": "2026-10-19T17:00:00Z", "exercises": [
            {"exercise": "Pec Deck (Machine, Acme)", "sets": [{"weightLb": 100, "reps": 12}]}]})
        text, err = self.tool("delete_exercise", id=acme)
        self.assertTrue(err)
        self.assertIn("merge-into", text)
        self.ok("delete_exercise", id=acme, merge_into=bench)
        hist = self.ok("exercise_history", id=bench)
        self.assertEqual(len(hist), 1)

    def test_put_workout_then_prs_and_history(self):
        bench, _, _ = self.seed()
        self.ok("put_workout", workout={"title": "Chest", "startedAt": "2026-10-19T17:00:00Z", "endedAt": "2026-10-19T18:00:00Z",
                                         "exercises": [{"exercise": "Bench Press (Barbell)", "sets": [{"weightLb": 185, "reps": 5}, {"weightLb": 205, "reps": 3}]}]})
        prs = self.ok("exercise_prs", id=bench)
        self.assertAlmostEqual(prs["heaviestKg"], 205 / 2.2046226218, places=2)
        shown = self.ok("get_exercise", id=bench)
        self.assertEqual(shown["usage"]["workouts"], 1)

    def test_sql_is_read_only_and_schema_lists_tables(self):
        self.seed()
        rows = self.ok("sql", query="select count(*) as n from exercises")
        self.assertEqual(rows["rows"], [[2]])
        text, err = self.tool("sql", query="delete from exercises")
        self.assertTrue(err)
        self.assertEqual(self.ok("sql", query="select count(*) from exercises")["rows"], [[2]])
        self.assertIn("workout_sets", json.dumps(self.ok("schema")))

    def test_reorder_and_undo_several(self):
        self.seed()
        second = self.ok("put_routine", routine={"title": "Legs"})["id"]
        first = self.ok("list_routines")[0]["id"]
        self.ok("reorder_routines", ids=[second, first])
        self.assertEqual([r["title"] for r in self.ok("list_routines")], ["Legs", "Chest"])
        self.ok("undo_claude", last=2)
        self.assertEqual([r["title"] for r in self.ok("list_routines")], ["Chest"])

    def test_text_that_starts_with_a_dash_is_not_taken_for_an_option(self):
        self.seed()
        result = self.ok("remove_exercise_from_routines", names=["-weird"])
        self.assertFalse(result["applied"])

    def test_errors_are_reported_not_raised(self):
        self.seed()
        text, err = self.tool("put_routine", routine={"title": "X", "exercises": [{"exercise": "No Such Thing"}]})
        self.assertTrue(err)
        self.assertIn("No Such Thing", text)
        text, err = self.tool("get_routine")
        self.assertTrue(err)
        self.assertIn("missing argument", text)
        self.assertTrue(self.tool("nonsense")[1])

    def test_everything_claude_does_is_attributed_and_listed(self):
        self.seed()
        changes = self.ok("changes", by="claude")
        self.assertEqual(len(changes), 3)
        self.assertTrue(all(c["author"] == "claude" for c in changes))


    def test_recovery_round_trip_for_eight_sleep_nights(self):
        saved = self.ok("put_recovery", entries=[{"date": "2026-10-20", "source": "eight_sleep", "sleepSeconds": 27000, "sleepScore": 75, "hrvMs": 60}])
        self.assertEqual(saved["saved"], 1)
        rows = self.ok("list_recovery", from_date="2026-10-20")
        self.assertEqual(rows[0]["sleepScore"], 75)
        both = self.ok("sql", query="select w.title, r.sleep_score from recovery r join workouts w on 1 = 1")
        self.assertEqual(both["rows"], [])
        schema = {t["name"]: t for t in self.call("tools/list")["result"]["tools"]}
        self.assertEqual(schema["put_recovery"]["inputSchema"]["properties"]["entries"]["items"], {"type": "object"})


    def test_search_text_that_starts_with_a_dash_is_not_an_option(self):
        self.seed()
        text, err = self.tool("list_exercises", match="-x")
        self.assertFalse(err, text)
        self.assertEqual(json.loads(text), [])


    def test_changes_reach_the_hub_without_a_manual_sync(self):
        import socket
        base = os.path.dirname(self.db)
        hub_db, tokens = os.path.join(base, "hub.sqlite"), os.path.join(base, "tokens.json")
        with open(tokens, "w") as f:
            json.dump({"tok": "test"}, f)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        hub = subprocess.Popen([FORGE_BIN, "sync-serve", "--db", hub_db, "--tokens", tokens, "--port", str(port)], stdout=subprocess.PIPE, text=True)
        try:
            self.assertIn("listening", hub.stdout.readline())
            setup = subprocess.run([FORGE_BIN, "sync-setup", "--url", f"http://127.0.0.1:{port}", "--token", "tok", "--db", self.db], capture_output=True, text=True)
            self.assertEqual(setup.returncode, 0, setup.stderr)
            self.ok("put_routine", routine={"title": "Synced by the tool"})
            on_hub = subprocess.run([FORGE_BIN, "routine", "list", "--db", hub_db], capture_output=True, text=True).stdout
            self.assertIn("Synced by the tool", on_hub)
        finally:
            hub.terminate()
            hub.wait()
            hub.stdout.close()


if __name__ == "__main__":
    unittest.main()
