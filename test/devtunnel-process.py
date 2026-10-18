#!/usr/bin/env python3
"""Exercise real process lifetimes with inert children and no sockets."""
import os
import pty
import select
import signal
import subprocess
import sys
import time

command, work = sys.argv[1:]
with open(os.environ["RECORD"], "a"):
    pass
unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
try:
    for answer in (b"n\n", b"y\n"):
        master, slave = pty.openpty()
        before = os.path.getsize(os.environ["RECORD"])
        process = subprocess.Popen([command, "delete", "fixture"], stdin=slave,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.close(slave)
        try:
            assert select.select([process.stdout], [], [], 10)[0], "confirmation prompt missing"
            prompt = os.read(process.stdout.fileno(), 65536)
            assert b"[y/N]" in prompt, prompt
            os.write(master, answer)
            _, error = process.communicate(timeout=10)
            assert process.returncode == 0, error
            after = os.path.getsize(os.environ["RECORD"])
            assert (after == before) if answer == b"n\n" else (after > before)
        finally:
            os.close(master)
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    for sig in (signal.SIGINT, signal.SIGTERM):
        pid_file = work + "/child"
        env = dict(os.environ, FAKE_CHILD=pid_file)
        process = subprocess.Popen([command, "host"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            assert select.select([process.stdout], [], [], 10)[0], "foreground output did not stream"
            assert process.stdout.readline() == b"ready\n"
            with open(pid_file) as record:
                child = int(record.read())
            process.send_signal(sig)
            _, error = process.communicate(timeout=10)
            assert process.returncode == 128 + sig, (process.returncode, error)
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError("owned child survived cancellation")
            assert unrelated.poll() is None, "unrelated process was terminated"
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    start = time.monotonic()
    result = subprocess.run([command, "list", "--timeout", "1"], env=dict(os.environ, FAKE_WAIT="1"),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode != 0 and b"timed out" in result.stderr
    assert time.monotonic() - start < 5
finally:
    unrelated.terminate()
    unrelated.wait(timeout=10)
