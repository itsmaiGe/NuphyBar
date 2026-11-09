"""Verify the installed app recovers a missed ending beyond its per-check read budget."""
import datetime
from contextlib import contextmanager
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

helper = Path.home() / "Applications/NuphyBar.app/Contents/Helpers/agent-light"
state_path = Path.home() / "Library/Application Support/AgentLight/state-v2.json"
session = str(uuid.uuid4())


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def snapshot():
    value = json.loads(state_path.read_text())
    record = next((v for k, v in zip(value["sessions"][::2], value["sessions"][1::2])
                   if k["sessionID"] == session), None)
    return value, record


def wait_closed(after):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        value, record = snapshot()
        closed = value.get("claudeClosedAt", {}).get(session, 0)
        if closed >= after:
            assert record is None or set(record["status"]) == {"complete"}
            return
        time.sleep(0.1)
    raise AssertionError("installed app did not confirm the paged ending")


@contextmanager
def fixture_directory():
    folder = tempfile.mkdtemp(prefix="nuphybar-paged-recovery-")
    try:
        yield folder
    except BaseException:
        # Keep evidence available to reconciliation if a regression prevents completion.
        print(json.dumps({"preserved_fixture": folder, "session": session}), flush=True)
        raise
    else:
        shutil.rmtree(folder)


with fixture_directory() as folder:
    transcript = Path(folder) / f"{session}.jsonl"

    def append(event):
        with transcript.open("a") as output:
            output.write(json.dumps({"sessionId": session, **event}) + "\n")

    def begin(identity):
        append({"type": "user", "uuid": identity, "timestamp": timestamp(),
                "message": {"role": "user", "content": "Local lifecycle fixture."}})
        subprocess.run([str(helper), "hook", "claude-code", "UserPromptSubmit"],
                       input=json.dumps({"session_id": session, "transcript_path": str(transcript)}),
                       text=True, check=True)

    def finish(parent):
        time.sleep(0.03)
        ended = time.time()
        append({"type": "assistant", "uuid": str(uuid.uuid4()), "parentUuid": parent,
                "timestamp": timestamp(),
                "message": {"role": "assistant", "stop_reason": "end_turn",
                            "content": [{"type": "text", "text": "Local fixture finished."}]}})
        wait_closed(int(ended))

    begin("first-root")
    with transcript.open("a") as output:
        padding = json.dumps({"type": "last-prompt", "sessionId": session, "padding": "x" * 512}) + "\n"
        for _ in range(5_000):
            output.write(padding)
    assert transcript.stat().st_size > 2 * 1024 * 1024
    time.sleep(6)
    value, record = snapshot()
    assert record and set(record["status"]) == {"working"}
    assert value.get("claudeClosedAt", {}).get(session) is None
    # No ending hook is sent. Only the installed app's periodic reconciliation can close this record.
    finish("first-root")
    print(json.dumps({"paged_missed_ending": "passed", "bytes": transcript.stat().st_size}), flush=True)
    begin("second-root")
    time.sleep(6)
    _, record = snapshot()
    assert record and set(record["status"]) == {"working"}, "old ending cleared a new task"
    finish("second-root")
    print(json.dumps({"new_task_preserved": "passed", "manual_state_cleanup": False}), flush=True)
