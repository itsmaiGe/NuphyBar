"""Exercise installed Claude hooks against a loopback-only API error."""
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

requested = threading.Event()


class LocalError(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"type": "error", "error": {
            "type": "invalid_request_error", "message": "NuphyBar local failure test"}}).encode()
        self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        requested.set()


binary = os.environ.get("NUPHYBAR_CLAUDE_BINARY") or shutil.which("claude")
assert binary, "Claude Code is required"
home = Path.home()
settings_path = home / ".claude/settings.json"
configured = json.loads(subprocess.check_output(["jq", "-c", ".hooks", str(settings_path)]))
selected = {}
for event, groups in configured.items():
    for group in groups:
        handlers = [hook for hook in group.get("hooks", [])
                    if "NuphyBar.app/Contents/Helpers/agent-light" in hook.get("command", "")]
        if handlers:
            selected.setdefault(event, []).append({**group, "hooks": handlers})
settings = {"hooks": selected}
helper = os.environ.get("NUPHYBAR_HELPER")
if helper:
    settings["hooks"] = {event: [{"hooks": [{"type": "command", "timeout": 10,
        "command": f"{shlex.quote(helper)} hook claude-code {event}"}]}]
        for event in ["UserPromptSubmit", "Stop", "StopFailure"]}
else:
    assert settings["hooks"].get("StopFailure"), "installed StopFailure hook is missing"
session = str(uuid.uuid4())
server = ThreadingHTTPServer(("127.0.0.1", 0), LocalError)
threading.Thread(target=server.serve_forever, daemon=True).start()
state = home / "Library/Application Support/AgentLight/state-v2.json"
process = None
with tempfile.TemporaryDirectory(prefix="nuphybar-claude-failure-") as isolated:
    marker = Path(isolated) / "stopfailure-exit"
    # Observe the real installed command's exit independently of best-effort diagnostics.
    for group in settings["hooks"]["StopFailure"]:
        for hook in group["hooks"]:
            hook["command"] += '; hook_result=$?; printf "%s" "$hook_result" > ' + shlex.quote(str(marker))
            hook["command"] += '; exit "$hook_result"'
    environment = os.environ.copy()
    for key in ["ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDECODE",
                "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"]:
        environment.pop(key, None)
    environment.update({"CLAUDE_CONFIG_DIR": isolated,
        "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{server.server_port}",
        "ANTHROPIC_API_KEY": "sk-ant-local-test-only", "DISABLE_AUTOUPDATER": "1",
        "DISABLE_TELEMETRY": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"})
    try:
        process = subprocess.Popen([binary, "-p", "--input-format", "stream-json",
            "--output-format", "stream-json", "--verbose", "--tools", "",
            "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
            "--setting-sources", "", "--settings", json.dumps(settings),
            "--session-id", session, "--permission-mode", "dontAsk"],
            cwd=isolated, env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL)
        message = {"type": "user", "session_id": session,
            "message": {"role": "user", "content": "Local failure lifecycle test."}}
        process.stdin.write(json.dumps(message).encode() + b"\n")
        process.stdin.flush()
        buffer = b""
        result = None
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            if b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                event = json.loads(line)
                if event.get("type") == "result":
                    result = event
                    break
            elif select.select([process.stdout], [], [], 0.2)[0]:
                data = os.read(process.stdout.fileno(), 65536)
                if not data:
                    break
                buffer += data
        assert requested.is_set(), "Claude did not reach the loopback API"
        assert result and result.get("is_error"), "Claude did not report the API failure"
        query = '.sessions as $s | [range(0; $s|length; 2) as $i | '
        query += 'select($s[$i].sessionID==$session) | $s[$i+1].status | keys[0]]'
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            statuses = json.loads(subprocess.check_output(["jq", "-c", "--arg", "session", session, query, str(state)]))
            if marker.exists() and marker.read_text() == "0" and statuses == ["error"]:
                break
            time.sleep(0.1)
        assert marker.exists() and marker.read_text() == "0", "native StopFailure command did not complete successfully"
        if statuses != ["error"]:
            paths = list(Path(isolated).rglob(f"{session}.jsonl"))
            print(json.dumps({"unsettled_status": statuses, "local_logs": [str(path) for path in paths]}), flush=True)
            for path in paths:
                data = subprocess.check_output(["tail", "-n", "12", str(path)])
                metadata = subprocess.check_output(["jq", "-c",
                    '{type,timestamp,sessionId,uuid,parentUuid,isApiErrorMessage,stop_reason:.message.stop_reason}',
                    ], input=data)
                print(metadata.decode(), flush=True)
        assert statuses == ["error"], "failed Claude turn remained active"
        assert process.poll() is None, "Claude owner exited before cleanup was verified"
        print(json.dumps({"native_stopfailure": "passed", "status": statuses[0],
            "owner_still_alive": process.poll() is None}), flush=True)
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        server.shutdown()
        server.server_close()
