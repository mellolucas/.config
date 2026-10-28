#!/bin/sh
# OpenCode reads the shared agent instructions through opencode.jsonc: its
# private server, offline and logged out, shows their text to a stand-in model
# on localhost. The home is temporary, with agents/ linked into a custom
# XDG_CONFIG_HOME as the installer links it.
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-opencode.XXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
server=
trap '[ -z "$server" ] || kill "$server" 2>/dev/null; rm -rf "$test_root"' EXIT
trap 'exit 1' HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

home="$test_root/home"
config="$home/config"
mkdir -p "$config/opencode" "$test_root/tmp" "$test_root/work"
cp "$repo/opencode/opencode.jsonc" "$config/opencode/"
ln -s "$repo/agents" "$config/agents"

# An OpenAI-compatible model that records each request and answers "ok"
python3 - "$test_root/requests" > "$test_root/port" <<'EOF' &
import http.server, json, socketserver, sys

class Model(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(sys.argv[1], "a") as log:
            log.write(json.dumps(request) + "\n")
        choice = {"index": 0, "delta": {"role": "assistant", "content": "ok"}, "finish_reason": "stop"}
        chunk = {"id": "1", "object": "chat.completion.chunk", "created": 0, "model": "model", "choices": [choice]}
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.wfile.write(b"data: " + json.dumps(chunk).encode() + b"\n\ndata: [DONE]\n\n")

with socketserver.TCPServer(("127.0.0.1", 0), Model) as model:
    print(model.server_address[1], flush=True)
    model.serve_forever()
EOF
server=$!
tries=0
until [ -s "$test_root/port" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || fail 'the stand-in model did not start'
  sleep 0.1
done

provider='{"model":"stand-in/model","providers":{"stand-in":{"env":["STAND_IN_KEY"],"package":"@opencode/ai/providers/openai-compatible","settings":{"baseURL":"http://127.0.0.1:'"$(cat "$test_root/port")"'/v1"},"models":{"model":{}}}}}'
(
  cd "$test_root/work"
  env -i PATH="$PATH" HOME="$home" TMPDIR="$test_root/tmp" TERM=dumb \
    XDG_CONFIG_HOME="$config" XDG_DATA_HOME="$home/data" \
    XDG_STATE_HOME="$home/state" XDG_CACHE_HOME="$home/cache" \
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 NO_PROXY=127.0.0.1 \
    OPENCODE_DISABLE_MODELS_FETCH=1 OPENCODE_DISABLE_AUTOUPDATE=1 \
    OPENCODE_CONFIG_CONTENT="$provider" STAND_IN_KEY=none \
    opencode run --standalone hello
) > "$test_root/run.log" 2>&1 || fail "opencode run: $(cat "$test_root/run.log")"

if ! python3 - "$test_root/requests" "$repo/agents/instructions.md" <<'EOF'; then
import json, sys

def texts(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from texts(item)
    elif isinstance(value, list):
        for item in value:
            yield from texts(item)

instructions = open(sys.argv[2]).read().strip()
with open(sys.argv[1]) as log:
    sys.exit(not any(instructions in text for line in log for text in texts(json.loads(line))))
EOF
  fail 'the model never saw agents/instructions.md'
fi

printf 'ok: opencode reads the shared agent instructions\n'
