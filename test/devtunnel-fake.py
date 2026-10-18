#!/usr/bin/env python3
"""Offline fixture; never authenticates, opens sockets, or invokes a real CLI."""
import json
import os
import signal
import subprocess
import sys
import time

with open(os.environ["RECORD"], "a") as record:
    record.write(json.dumps(sys.argv[1:]) + "\n")
if sys.argv[1:] == ["--version"]:
    print(os.environ.get("FAKE_VERSION", "Tunnel CLI version: 1.0.2115"))
    sys.exit(int(os.environ.get("FAKE_VERSION_STATUS", "0")))
if os.environ.get("FAKE_CHILD"):
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
    with open(os.environ["FAKE_CHILD"], "w") as record:
        record.write(str(child.pid))
    def terminate(_signum, _frame):
        child.wait()
        sys.exit(0)
    signal.signal(signal.SIGTERM, terminate)
    print("ready", flush=True)
    while True:
        time.sleep(1)
if os.environ.get("FAKE_WAIT"):
    print("ready", flush=True)
    time.sleep(120)
sys.stdout.write(os.environ.get("FAKE_OUTPUT", '{"tunnels":[{"tunnelId":"fixture"}],"continuationToken":"next"}'))
sys.stdout.flush()
sys.stderr.write(os.environ.get("FAKE_ERROR", ""))
sys.exit(int(os.environ.get("FAKE_STATUS", "0")))
