#!/usr/bin/env python3
"""Exercise installed Bash/readline or zsh/ZLE without executing bin commands."""

import os
import pty
import select
import shlex
import shutil
import subprocess
import sys
import time


root, work, rc = sys.argv[1:4]
shell = sys.argv[4] if len(sys.argv) > 4 else "zsh"
os.makedirs(os.path.join(work, "folder name"), exist_ok=True)
for name in ("config file.json", "--literal file", "folder name/file one.json",
             "$(touch SHOULD_NOT_EXIST) file"):
    with open(os.path.join(work, name), "w", encoding="utf-8") as stream:
        stream.write("{}")
env_home = os.environ.get("COPILOT_HOME", os.path.join(work, "copilot"))
os.makedirs(env_home, exist_ok=True)
with open(os.path.join(env_home, "mcp config.json"), "w", encoding="utf-8") as stream:
    stream.write("{}")
with open(os.path.join(os.environ["HOME"], "personal file.json"), "w", encoding="utf-8") as stream:
    stream.write("{}")

with open(os.path.join(work, ".zshenv"), "w", encoding="utf-8") as stream:
    stream.write('source "$REPO_ROOT/test/completion-zsh-env.zsh"\n')
master, slave = pty.openpty()
env = dict(os.environ, TERM="xterm", SHM_COMPLETION_RC=rc, SHM_COMPLETION_WORK=work,
           ZDOTDIR=work, HISTFILE=os.path.join(work, "history"))
argv = [shutil.which("zsh"), "-d", "-i"] if shell == "zsh" else [
    shutil.which("bash"), "--noprofile", "--norc", "-i"]
process = subprocess.Popen(
    argv, stdin=slave, stdout=slave, stderr=slave,
    cwd=work, env=env, start_new_session=True,
)
os.close(slave)


def read_until(marker, timeout=10):
    data = b""
    deadline = time.monotonic() + timeout
    while marker not in data and time.monotonic() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                data += os.read(master, 65536)
            except OSError:
                break
    if marker not in data:
        raise AssertionError(shell + " did not respond: " + repr(data))
    return data


try:
    # The prompt and capture widget delimit real input buffers, not display
    # listings. Control-X clears the input so completed commands never execute.
    if shell == "zsh":
        setup = b"""
source "$SHM_COMPLETION_RC"
PROMPT='SHM_READY> '; RPROMPT=''
bindkey '^I' complete-word
_shm_capture_buffer() { print -r -- "SHM_${:-CAPTURE}<$BUFFER>SHM_${:-END}"; zle .kill-whole-line; }
zle -N _shm_capture_buffer
bindkey '^X' _shm_capture_buffer
print -r -- "SHM_${:-SETUP_DONE}"
"""
    else:
        setup = b"""
source "$SHM_COMPLETION_RC"
PS1='SHM_READY> '; PS2=''
_shm_capture_buffer() { printf 'SHM_%s<%s>SHM_%s\\n' CAPTURE "$READLINE_LINE" END; READLINE_LINE=''; READLINE_POINT=0; }
bind -x '"\\C-x":_shm_capture_buffer'
printf 'SHM_%s\\n' SETUP_DONE
"""
    os.write(master, setup)
    read_until(b"SHM_SETUP_DONE\r\n")
    cases = [
        ("copilot-session ren", ["copilot-session", "rename"]),
        ("git-worktree-new --ki", ["git-worktree-new", "--kind"]),
        ("package-update --provider np", ["package-update", "--provider", "npm"]),
        ("dotnet-sdk-install --quality pre", ["dotnet-sdk-install", "--quality", "preview"]),
        ('dev-setup apply "config f"', ["dev-setup", "apply", "config file.json"]),
        ("dotnet-sdk-install --install-dir fol", ["dotnet-sdk-install", "--install-dir", "folder name/"]),
        ("start-vscode -- --lit", ["start-vscode", "--", "--literal file"]),
        ('start-copilot --usage-output-file "folder name/file o"',
         ["start-copilot", "--usage-output-file", "folder name/file one.json"]),
        ("start-copilot -- --mo", ["start-copilot", "--", "--mo"]),
        ("start-copilot --auto-tier=in", ["start-copilot", "--auto-tier=intelligence"]),
        ("start-copilot --dynamic-retrieval=skills=of",
         ["start-copilot", "--dynamic-retrieval=skills=off"]),
        ("start-copilot --additional-mcp-config @~/mcp",
         ["start-copilot", "--additional-mcp-config", "@~/mcp config.json"]),
        ("copilot-mcp add server --tools ", ["copilot-mcp", "add", "server", "--tools", "*"]),
        ('start-vscode "$(touch SHOULD_NOT_EXIST) f"',
         ["start-vscode", "$(touch SHOULD_NOT_EXIST) file"]),
        ("start-vscode ~/personal", ["start-vscode", "~/personal file.json"]),
    ]
    for text, expected in cases:
        os.write(master, text.encode("utf-8") + b"\t")
        time.sleep(0.2)
        os.write(master, b"\x18")
        data = read_until(b">SHM_END")
        capture = data.rsplit(b"SHM_CAPTURE<", 1)[1].split(b">SHM_END", 1)[0]
        try:
            actual = shlex.split(capture.decode("utf-8"))
        except ValueError as error:
            raise AssertionError((text, capture, data)) from error
        if actual != expected:
            raise AssertionError((text, actual, expected, data))
        if expected[-1] == "*" and not any(quoted in capture for quoted in (b"\\*", b"'*'", b'"*"')):
            raise AssertionError("tools wildcard was not quoted: " + repr(capture))
    if os.path.exists(os.path.join(work, "SHOULD_NOT_EXIST")):
        raise AssertionError("completion evaluated a command substitution")
    print("{} completion: {} cases passed".format(shell, len(cases)))
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    os.close(master)
