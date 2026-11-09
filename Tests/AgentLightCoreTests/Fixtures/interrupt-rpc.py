"""Exercise native Interrupt hooks against a loopback-only stalled model stream."""
import json
import os
import select
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

request_seen = threading.Event()
release_stream = threading.Event()

class LocalModel(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        event = {"type": "response.created", "response": {
            "id": "local_lifecycle_test", "object": "response", "created_at": int(time.time()),
            "status": "in_progress", "model": "nuphybar-local-test", "output": []}}
        self.wfile.write(("event: response.created\ndata: " + json.dumps(event) + "\n\n").encode())
        self.wfile.flush()
        request_seen.set()
        release_stream.wait(30)

server = ThreadingHTTPServer(("127.0.0.1", 0), LocalModel)
threading.Thread(target=server.serve_forever, daemon=True).start()
provider = '{name="NuphyBar local test",base_url="http://127.0.0.1:%d/v1",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}' % server.server_port
binary = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
process = subprocess.Popen([binary, "-c", 'model_provider="nuphybar_test"',
                            "-c", "model_providers.nuphybar_test=" + provider, "app-server"],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
buffer = b""
notifications = []

def send(message):
    process.stdin.write(json.dumps(message).encode() + b"\n")
    process.stdin.flush()

def receive(timeout=20):
    global buffer
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if b"\n" in buffer:
            line, buffer = buffer.split(b"\n", 1)
            return json.loads(line)
        if select.select([process.stdout], [], [], 0.2)[0]:
            data = os.read(process.stdout.fileno(), 65536)
            if not data:
                raise RuntimeError("app-server exited")
            buffer += data
    raise TimeoutError("RPC response timed out")

def response(request_id):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        message = receive(max(0.1, deadline - time.monotonic()))
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message["result"]
        notifications.append(message)
    raise TimeoutError("RPC request timed out")

try:
    send({"id": 1, "method": "initialize", "params": {
        "clientInfo": {"name": "nuphybar_interrupt_test", "version": "0.1"},
        "capabilities": {"experimentalApi": True}}})
    response(1)
    send({"method": "initialized"})
    send({"id": 2, "method": "hooks/list", "params": {"cwds": [os.getcwd()]}})
    listing = response(2)
    interrupt = [hook for entry in listing["data"] for hook in entry["hooks"]
                 if hook.get("eventName") == "interrupt"
                 and "NuphyBar.app/Contents/Helpers/agent-light" in hook.get("command", "")]
    assert len(interrupt) == 1 and interrupt[0]["trustStatus"] == "trusted" and interrupt[0]["enabled"]
    send({"id": 3, "method": "config/read", "params": {"includeLayers": False}})
    config = response(3)["config"]
    disabled_mcp = {name: {"enabled": False} for name in config.get("mcp_servers", {})}
    send({"id": 4, "method": "thread/start", "params": {
        "model": "nuphybar-local-test", "modelProvider": "nuphybar_test", "cwd": os.getcwd(),
        "ephemeral": True, "approvalPolicy": "never", "sandbox": "read-only",
        "config": {"mcp_servers": disabled_mcp, "features": {"apps": False, "plugins": False}}}})
    thread_id = response(4)["thread"]["id"]
    send({"id": 5, "method": "turn/start", "params": {
        "threadId": thread_id,
        "input": [{"type": "text", "text": "Local lifecycle test. The mock stream intentionally stalls."}]}})
    turn_id = response(5)["turn"]["id"]
    assert request_seen.wait(15), "the loopback model was not reached"
    print(json.dumps({"stage": "running", "thread": thread_id, "turn": turn_id, "owner_pid": process.pid}), flush=True)
    time.sleep(2)
    send({"id": 6, "method": "turn/interrupt", "params": {"threadId": thread_id, "turnId": turn_id}})
    response(6)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        done = [n for n in notifications if n.get("method") == "hook/completed"
                and n.get("params", {}).get("run", {}).get("eventName") == "interrupt"]
        if done:
            run = done[-1]["params"]["run"]
            assert run["status"] == "completed", run
            print(json.dumps({"stage": "interrupt_hook_completed", "run": run}), flush=True)
            break
        notifications.append(receive(max(0.1, deadline - time.monotonic())))
    else:
        raise RuntimeError("the native Interrupt hook did not complete")
    assert process.poll() is None
    state_path = "/Users/minqiu/Library/Application Support/AgentLight/state-v2.json"
    check = subprocess.run(["jq", "-e", "--arg", "session", thread_id,
                            ".sessions[] | select(.sessionID? == $session)", state_path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    assert check.returncode == 4, "interrupted task remained active while its owner was alive"
    if "--preserve-session" in sys.argv:
        session = sys.argv[sys.argv.index("--preserve-session") + 1]
        check = subprocess.run(["jq", "-e", "--arg", "session", session,
                                ".sessions[] | select(.sessionID? == $session)", state_path],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        assert check.returncode == 0, "the other active task was unexpectedly removed"
    print("Interrupted task removed while owner is alive; other requested task preserved.", flush=True)
    print("Native task owner remains alive for ten seconds after interruption.", flush=True)
    time.sleep(10)
finally:
    release_stream.set()
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    server.shutdown()
