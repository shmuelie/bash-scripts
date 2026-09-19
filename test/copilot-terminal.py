#!/usr/bin/env python3
"""Run the real launcher against a native mock, never a live Copilot process."""

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
WORK = Path(sys.argv[1])
MODE = sys.argv[2]
RESET = b"\x1b[?2026;2004;1049;1006;1004;1003;1000l\x1b[=0u"
ENV = dict(os.environ, COPILOT_HOME=str(WORK / "home"),
           HOME=str(WORK / "home"), PATH=f"{WORK / 'bin'}:{ROOT / 'bin'}:{os.environ['PATH']}")
ENV.pop("TMUX", None)
LOG = WORK / "terminal-output"
SOCKET = WORK / "tmux.sock"


def tmux(*args):
    return subprocess.check_output(["tmux", "-S", str(SOCKET), *args],
                                   env=ENV, stderr=subprocess.STDOUT).decode().strip()


def output():
    return LOG.read_bytes() if LOG.exists() else b""


def wait_for(predicate, description):
    until = time.monotonic() + 10
    while time.monotonic() < until:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {description}\n{output()!r}")


def process_exists(pid):
    return Path(f"/proc/{pid}").exists()


if MODE == "redirected":
    for status in (0, 7):
        result = subprocess.run([str(ROOT / "bin/start-copilot"), "--no-resume"],
                                input=b"done\n", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=dict(ENV, MOCK_EXIT=str(status)), timeout=10)
        assert result.returncode == status, result
        assert b"job control" not in result.stderr, result.stderr
        assert RESET not in result.stdout, result.stdout
    sys.exit(0)

try:
    tmux("-f", "/dev/null", "new-session", "-d", "-s", "test",
         "bash --noprofile --norc -i")
    tmux("set-option", "-t", "test", "automatic-rename", "on")
    tmux("set-option", "-t", "test", "automatic-rename-format", "#{pane_current_command}")
    tmux("pipe-pane", "-t", "test:0.0", f"cat > {shlex.quote(str(LOG))}")
    status = 7 if MODE in ("failure", "suspend-failure") else 0
    command = (f"MOCK_EXIT={status} {shlex.quote(str(ROOT / 'bin/start-copilot'))} "
               "--no-resume; printf 'WRAPPER_EXIT=%s\\n' \"$?\"")
    tmux("send-keys", "-t", "test:0.0", command, "Enter")
    wait_for(lambda: re.search(rb"MOCK_READY pid=(\d+) pgid=(\d+) foreground=(\d+) wrapper=(\d+)\r?\n", output()),
             "native mock ready")
    match = re.search(rb"MOCK_READY pid=(\d+) pgid=(\d+) foreground=(\d+) wrapper=(\d+)", output())
    pid, pgid, foreground, wrapper = map(int, match.groups())
    assert pid == pgid == foreground, (pid, pgid, foreground)
    wait_for(lambda: tmux("display-message", "-p", "-t", "test:0.0",
                         "#{pane_current_command}") == "copilot", "copilot foreground identity")
    wait_for(lambda: tmux("display-message", "-p", "-t", "test:0.0",
                         "#{window_name}") == "copilot", "automatic window naming")

    if MODE.startswith("suspend"):
        for _ in range(2):
            tmux("send-keys", "-t", "test:0.0", "C-z")
            wait_for(lambda: tmux("display-message", "-p", "-t", "test:0.0",
                                 "#{pane_current_command}") == "bash", "caller regained terminal")
            wait_for(lambda: b") + Stopped" in output() or b"Stopped" in output(), "stopped job report")
            assert process_exists(pid), "native child disappeared while suspended"
            assert RESET not in output(), output()
            wait_for(lambda: "\nState:\tT" in Path(f"/proc/{pid}/status").read_text(),
                     "native child stopped")
            wait_for(lambda: "\nState:\tT" in Path(f"/proc/{wrapper}/status").read_text(),
                     "wrapper stopped")
            tmux("send-keys", "-t", "test:0.0",
                 "fg; printf 'WRAPPER_EXIT=%s\\n' \"$?\"", "Enter")
            wait_for(lambda: tmux("display-message", "-p", "-t", "test:0.0",
                                 "#{pane_current_command}") == "copilot", "foreground resume")
    if MODE in ("interrupt", "suspend"):
        tmux("send-keys", "-t", "test:0.0", "C-c")
        status = 130
    else:
        tmux("send-keys", "-t", "test:0.0", "done", "Enter")
    wait_for(lambda: re.search(rb"WRAPPER_EXIT=" + str(status).encode() + rb"\r?\n", output()),
             f"wrapper status {status}")
    assert (RESET in output()) == (status != 0), output()
    wait_for(lambda: not process_exists(pid), "native child reaped")
    wait_for(lambda: not process_exists(wrapper), "wrapper exited")
    wait_for(lambda: tmux("display-message", "-p", "-t", "test:0.0",
                         "#{pane_current_command}") == "bash", "shell terminal ownership")
except Exception:
    print(repr(output()), file=sys.stderr)
    raise
finally:
    if SOCKET.exists():
        subprocess.run(["tmux", "-S", str(SOCKET), "kill-server"],
                       env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
