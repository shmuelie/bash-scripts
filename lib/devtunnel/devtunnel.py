#!/usr/bin/env python3
"""Argument-safe Shmuelie.DevTunnel port with owned-process supervision."""

import argparse
import ipaddress
import json
import os
import re
import selectors
import shutil
import signal
import subprocess
import sys
from urllib.parse import urlsplit


INSTALL = "Install Microsoft devtunnel 1.0.2115 or compatible 1.x: https://learn.microsoft.com/azure/developer/dev-tunnels/get-started"
SCOPES = ("create", "manage", "manage:ports", "host", "inspect", "connect")
PROTOCOLS = ("http", "https", "auto")


class CommandError(Exception):
    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


def integer(minimum, maximum):
    def parse(value):
        if not re.fullmatch(r"[0-9]{1,10}", value) or not minimum <= int(value) <= maximum:
            raise argparse.ArgumentTypeError("expected an integer from %s to %s" % (minimum, maximum))
        return str(int(value))
    return parse


def expiration(value):
    match = re.fullmatch(r"([1-9][0-9]{0,2})([hd])", value)
    if not match or int(match[1]) > (720 if match[2] == "h" else 30):
        raise argparse.ArgumentTypeError("expiration must be 1h-720h or 1d-30d")
    return value


def tunnel_id(value):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*", value):
        raise argparse.ArgumentTypeError("invalid tunnel ID")
    return value


def nonempty(value):
    if not value.strip():
        raise argparse.ArgumentTypeError("value must not be empty")
    return value


def address(value):
    try:
        ipaddress.ip_address(value)
    except ValueError:
        raise argparse.ArgumentTypeError("interface must be an IP address") from None
    return value


def uri(value):
    try:
        parsed = urlsplit(value)
        if (parsed.scheme not in ("http", "https", "ws", "wss", "tcp", "udp", "ssh")
                or not parsed.hostname or parsed.username is not None
                or parsed.password is not None or re.search(r"[\s\\]", value)):
            raise ValueError()
        parsed.port
    except ValueError:
        raise argparse.ArgumentTypeError("expected an absolute diagnostic URI without credentials") from None
    return value


def parser():
    root = argparse.ArgumentParser(
        prog="dev-tunnel",
        description="Wrap devtunnel 1.0.2115/compatible 1.x. Management returns CLI JSON; foreground commands stream text.",
        epilog="No implicit install or login. See docs/devtunnel.md for mappings, access safety, and workflows.",
        allow_abbrev=False)
    commands = root.add_subparsers(dest="command", required=True)

    def add(parent, name, options=(), target=False, stream=False, mutate=False, destructive=False):
        p = parent.add_parser(name, allow_abbrev=False)
        p.set_defaults(stream=stream, mutate=mutate, destructive=destructive)
        p.add_argument("--dry-run", "--whatif", action="store_true", help="preview without discovering or executing the CLI")
        p.add_argument("--json", action="store_true", help="management output is always JSON; not supported for streams")
        p.add_argument("--yes", action="store_true", help="explicitly approve destructive operations without a TTY")
        p.add_argument("--confirm", action="store_true", help="require interactive confirmation before execution")
        p.add_argument("--timeout", type=integer(1, 3600), default="60", help="management/version timeout in seconds (default: 60)")
        if target:
            p.add_argument("id", nargs="?", type=tunnel_id)
        repeated = ("labels", "all-labels", "add-labels", "remove-labels", "scopes")
        for option in options:
            spec = {"dest": option.replace("-", "_")}
            if option in ("github", "use-device-code-auth", "allow-anonymous", "anonymous", "tenant", "deny", "ping"):
                spec["action"] = "store_true"
            else:
                spec["type"] = {
                    "port-number": integer(1, 65535), "port": integer(1, 65535),
                    "limit": integer(1, 2147483647), "index": integer(0, 2147483647),
                    "size": integer(1, 2147483647), "interval": integer(1, 2147483647),
                    "expiration": expiration, "interface": address,
                }.get(option, str if option == "description" and name == "update" else nonempty)
                if option in repeated or (option == "port-number" and name == "host"):
                    spec["action"] = "append"
                if option == "scopes":
                    spec["choices"] = SCOPES
                if option == "protocol":
                    spec["choices"] = ("http", "https", "ssh", "tcp", "udp") if name == "echo" else PROTOCOLS
            p.add_argument("--" + option, **spec)
        return p

    add(commands, "version")
    users = commands.add_parser("user", allow_abbrev=False).add_subparsers(dest="operation", required=True)
    add(users, "login", ("github", "use-device-code-auth"), stream=True, mutate=True)
    add(users, "logout", mutate=True)
    add(users, "show")
    add(commands, "list", ("labels", "all-labels", "limit"))
    add(commands, "show", target=True)
    add(commands, "create", ("description", "labels", "expiration", "allow-anonymous"), target=True, mutate=True)
    add(commands, "update", ("description", "add-labels", "remove-labels", "expiration"), target=True, mutate=True)
    add(commands, "delete", target=True, mutate=True, destructive=True)
    add(commands, "delete-all", mutate=True, destructive=True)
    add(commands, "host", ("port-number", "protocol", "description", "labels", "expiration", "allow-anonymous"),
        target=True, stream=True, mutate=True)
    add(commands, "connect", target=True, stream=True, mutate=True)
    ports = commands.add_parser("port", allow_abbrev=False).add_subparsers(dest="operation", required=True)
    for name, options in (
            ("list", ()), ("show", ("port-number",)),
            ("create", ("port-number", "protocol", "description", "labels")),
            ("update", ("port-number", "description", "add-labels", "remove-labels")),
            ("delete", ("port-number",))):
        add(ports, name, options, target=True, mutate=name in ("create", "update", "delete"), destructive=name == "delete")
    access = commands.add_parser("access", allow_abbrev=False).add_subparsers(dest="operation", required=True)
    add(access, "list", ("port-number",), target=True)
    add(access, "create", ("port-number", "anonymous", "tenant", "organization", "repo", "deny", "scopes", "expiration", "index"),
        target=True, mutate=True)
    add(access, "delete", ("port-number", "index"), target=True, mutate=True, destructive=True)
    add(access, "reset", ("port-number",), target=True, mutate=True, destructive=True)
    token = add(commands, "token", ("scopes",), target=True, mutate=True)
    output = token.add_mutually_exclusive_group(required=True)
    output.add_argument("--output-file", help="create a new mode-0600 file; never overwrite an existing path")
    output.add_argument("--show-token", action="store_true", help="explicitly allow credential-bearing JSON on stdout")
    add(commands, "set", target=True, mutate=True)
    add(commands, "unset", mutate=True)
    add(commands, "clusters", ("ping",))
    add(commands, "limits")
    add(commands, "echo", ("port", "protocol", "interface"), stream=True, mutate=True)
    ping = add(commands, "ping", ("size", "interval"), stream=True, mutate=True)
    ping.add_argument("uri", type=uri)
    return root


def arguments(options, root):
    command = options.command
    operation = getattr(options, "operation", None)
    if options.stream and options.json:
        root.error("--json is only supported for management commands")
    if options.yes and options.confirm:
        root.error("choose --yes or --confirm, not both")
    if command == "set" and not options.id:
        root.error("set requires a tunnel ID")
    if command == "port" and operation != "list" and not options.port_number:
        root.error("port %s requires --port-number" % operation)
    if command == "access" and operation == "delete" and options.index is None:
        root.error("access delete requires --index")
    if command == "access" and operation == "create":
        if sum(bool(getattr(options, name)) for name in ("anonymous", "tenant", "organization", "repo")) != 1:
            root.error("access create requires exactly one of --anonymous, --tenant, --organization, --repo")
    if command == "token" and not options.scopes:
        root.error("token requires --scopes")
    if command == "echo" and options.port is None:
        root.error("echo requires --port")
    result = [command]
    if operation:
        result.append(operation)
    if getattr(options, "id", None):
        result.append(options.id)
    if command == "ping":
        result.append(options.uri)
    if command == "echo":
        result.extend((options.protocol or "http", "--port=" + options.port,
                       "--interface=" + (options.interface or "127.0.0.1")))
    excluded = {"command", "operation", "stream", "mutate", "destructive", "dry_run", "json",
                "yes", "confirm", "timeout", "id", "uri", "output_file", "show_token"}
    if command == "echo":
        excluded.update(("port", "protocol", "interface"))
    for key, value in vars(options).items():
        if key in excluded or value is None or value is False:
            continue
        flag = "--" + key.replace("_", "-")
        if value is True:
            result.append(flag)
        else:
            result.extend(flag + "=" + item for item in (value if isinstance(value, list) else [value]))
    if not options.stream and command != "version":
        result.append("--json")
    if command in ("delete", "delete-all"):
        result.append("--force")
    return result


def redact(text):
    text = re.sub(r"""(?i)(\b(?:access[_-]?token|refresh[_-]?token|id[_-]?token|authorization|client[_-]?secret)\b["']?\s*[:=]\s*["']?(?:bearer\s+)?)[^\s"',;]+""",
                  r"\1[REDACTED]", text)
    text = re.sub(r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*", "Bearer [REDACTED]", text)
    text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[REDACTED]", text)
    return re.sub(r"\b(?:gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+)\b", "[REDACTED]", text)


def stop(process):
    # Each child has its own session/process group. Never signal unrelated CLI instances.
    handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            process.wait()
            return
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def run(executable, args, timeout, stream=False, sensitive=False):
    process = subprocess.Popen([executable] + args, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        if stream:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ, sys.stdout)
                selector.register(process.stderr, selectors.EVENT_READ, sys.stderr)
                pending = {process.stdout: b"", process.stderr: b""}
                while selector.get_map():
                    for key, _ in selector.select():
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        data = pending[key.fileobj] + chunk
                        if chunk:
                            lines = data.split(b"\n")
                            pending[key.fileobj] = lines.pop()
                        else:
                            lines = [data]
                            selector.unregister(key.fileobj)
                        for line in lines:
                            if line or chunk:
                                key.data.write(redact(line.decode("utf-8", errors="replace")) + "\n")
                                key.data.flush()
            stdout, stderr = "", ""
            process.wait()
        else:
            stdout, stderr = process.communicate(timeout=timeout)
            stdout = stdout.decode("utf-8", errors="replace")
            stderr = stderr.decode("utf-8", errors="replace")
        if process.returncode:
            detail = "" if sensitive else redact(stderr).strip()
            raise CommandError("devtunnel failed (exit %s).%s" %
                               (process.returncode, "\n" + detail if detail else ""),
                               process.returncode if process.returncode > 0 else 128 - process.returncode)
        if stderr and not sensitive:
            print("Warning: " + redact(stderr).rstrip(), file=sys.stderr)
        return stdout
    except subprocess.TimeoutExpired:
        raise CommandError("devtunnel timed out after %s seconds." % timeout) from None
    finally:
        stop(process)
        process.stdout.close()
        process.stderr.close()


def main():
    root = parser()
    options = root.parse_args()
    args = arguments(options, root)
    if options.dry_run:
        print("What if: devtunnel " + json.dumps(args), file=sys.stderr)
        return
    if options.confirm or (options.destructive and not options.yes):
        if not sys.stdin.isatty():
            raise CommandError("Destructive/confirmed operations require a terminal or explicit --yes approval.")
        if input("Run devtunnel %s? [y/N] " % " ".join(args)).strip().lower() != "y":
            print("Declined; no command executed.", file=sys.stderr)
            return
    executable = shutil.which("devtunnel")
    if not executable:
        raise CommandError("devtunnel not found on PATH. " + INSTALL)
    version_text = run(executable, ["--version"], int(options.timeout), sensitive=True)
    match = re.search(r"^(?:Tunnel CLI version:\s*)?(\d+)\.(\d+)\.(\d+)(?:[+.\s-]|$)", version_text, re.M)
    if not match:
        raise CommandError("Cannot determine devtunnel version. " + INSTALL)
    version = tuple(int(part) for part in match.groups())
    if version[0] != 1 or version < (1, 0, 2115):
        raise CommandError("Unsupported devtunnel version %s. %s" % (".".join(match.groups()), INSTALL))
    if options.command == "version":
        print(json.dumps({"version": ".".join(match.groups()), "path": executable}))
        return
    if getattr(options, "allow_anonymous", False) or (
            getattr(options, "anonymous", False) and not options.deny):
        print("Warning: Anonymous access allows anyone on the internet who knows the tunnel address to connect to the exposed service.", file=sys.stderr)
    sensitive = options.command in ("user", "token")
    output = run(executable, args, int(options.timeout), options.stream, sensitive)
    if options.stream or not output.strip():
        return
    try:
        value = json.loads(output)
    except ValueError:
        raise CommandError("devtunnel returned invalid JSON; verify command support for --json.") from None
    text = json.dumps(value, ensure_ascii=True) + "\n"
    if options.command == "token" and options.output_file:
        # O_EXCL also rejects symlinks, and permissions apply at creation, not afterward.
        fd = os.open(options.output_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as destination:
            destination.write(text)
    else:
        sys.stdout.write(text)


def interrupted(signum, _frame):
    raise CommandError("dev-tunnel cancelled.", 128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except CommandError as error:
        print("Error: " + str(error), file=sys.stderr)
        sys.exit(error.status)
    except (OSError, EOFError) as error:
        print("Error: dev-tunnel: " + str(error), file=sys.stderr)
        sys.exit(1)
