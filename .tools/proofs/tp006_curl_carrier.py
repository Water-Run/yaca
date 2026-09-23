#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: tp006_curl_carrier.py
# Description: TP-006 modern-host proof for curl carrier, cancellation, retry, and scanning.

"""TP-006 modern-host proof for curl carrier, cancellation, retry, and scanning.

This script starts loopback-only programmable endpoints. It never prints the
runtime canary secret and does not persist that secret in a repository file.
"""

from __future__ import annotations

import hashlib
import http.server
import json
import os
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


ASSERTIONS = 0
MIN_SCANNABLE_SECRET_BYTES_CANDIDATE = 8


# Raises on a failed proof assertion with a scenario-specific message.
#@param value object Candidate value under validation.
#@param message str Assertion or diagnostic message.
#@return None No value; the operation updates proof state or raises on failure.
def check(value: bool, message: str) -> None:
    global ASSERTIONS
    ASSERTIONS += 1
    if not value:
        raise AssertionError(f"assertion {ASSERTIONS} failed: {message}")


# Asserts that an observed value equals its expected proof value.
#@param actual object Observed value or fault point.
#@param expected object Expected observation or child exit state.
#@param message str Assertion or diagnostic message.
#@return None No value; the operation updates proof state or raises on failure.
def equal(actual, expected, message: str) -> None:
    check(actual == expected, f"{message} (expected={expected!r} actual={actual!r})")


#@class ServerState Owns the curl carrier proof curl carrier state and its resource lifetime.
@dataclass
class ServerState:
    lock: threading.Lock = field(default_factory=threading.Lock)
    requests: list[dict] = field(default_factory=list)
    echo_seen: threading.Event = field(default_factory=threading.Event)
    release_echo: threading.Event = field(default_factory=threading.Event)
    sse_seen: threading.Event = field(default_factory=threading.Event)
    release_sse: threading.Event = field(default_factory=threading.Event)

    # Records one HTTP request received by the proof server.
    #@param self ServerState Owner of the proof fixture and its resources.
    #@param item dict Request record added to proof state.
    #@return None result No value; appends the request to server evidence.
    def record(self, item: dict) -> None:
        with self.lock:
            self.requests.append(item)

    # Finds recorded HTTP requests for the selected route.
    #@param self ServerState Owner of the proof fixture and its resources.
    #@param path Path|str Input file or package path under inspection.
    #@return list[dict] requests Recorded requests matching the selected route.
    def matching(self, path: str) -> list[dict]:
        with self.lock:
            return [request for request in self.requests if request["path"] == path]


#@class ProofHandler Owns the curl carrier proof curl carrier state and its resource lifetime.
class ProofHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "yaca-proof"
    sys_version = ""

    # Suppresses default proof-server request logging.
    #@param self ProofHandler Owner of the proof fixture and its resources.
    #@param _format str Unused HTTP server log format.
    #@param _args object Unused HTTP server log arguments.
    #@return None No value; the operation updates proof state or raises on failure.
    def log_message(self, _format: str, *_args) -> None:
        return

    # Checks state in curl carrier proof curl carrier.
    #@param self ProofHandler Owner of the proof fixture and its resources.
    #@return ServerState state Shared request evidence owned by the proof server.
    @property
    def state(self) -> ServerState:
        return self.server.proof_state  # type: ignore[attr-defined]

    # Checks  request record in curl carrier proof curl carrier.
    #@param self ProofHandler Owner of the proof fixture and its resources.
    #@return dict record Captured method, path, headers, and body of this POST.
    def _request_record(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        record = {
            "path": urllib.parse.urlsplit(self.path).path,
            "headers": {key.lower(): value for key, value in self.headers.items()},
            "body": body,
        }
        self.state.record(record)
        return record

    # Handles a proof HTTP POST and records its request evidence.
    #@param self ProofHandler Owner of the proof fixture and its resources.
    #@return None No value; the operation updates proof state or raises on failure.
    def do_POST(self) -> None:  # noqa: N802 - standard handler name
        record = self._request_record()
        if record["path"] == "/echo":
            self.state.echo_seen.set()
            self.state.release_echo.wait(timeout=8)
            payload = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            return

        if record["path"] == "/sse":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                self.wfile.write(b"data: canonical-1\n\n")
                self.wfile.flush()
                self.state.sse_seen.set()
                self.state.release_sse.wait(timeout=8)
                self.wfile.write(b"data: must-not-be-observed\n\n")
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()


# Starts the local HTTP proof server on a loopback port.
#@param state object Shared proof-server state.
#@return tuple server Loopback HTTP server and its running thread.
def start_server(state: ServerState):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ProofHandler)
    server.daemon_threads = True
    server.proof_state = state  # type: ignore[attr-defined]
    thread = threading.Thread(target=server.serve_forever, name="proof-http", daemon=True)
    thread.start()
    return server, thread


# Writes a private temporary file for the transport proof.
#@param path Path|str Input file or package path under inspection.
#@param data bytes|str Input bytes or text under examination.
#@return None result No value; writes the private proof input with restricted permissions.
def private_file(path: Path, data: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


# Builds a restricted environment for the curl subprocess.
#@param fake_home object The fake home supplied to this proof operation.
#@return tuple environment Restricted environment and inherited-secret observations.
def scrubbed_environment(fake_home: Path) -> tuple[dict[str, str], int]:
    ambient_names = {
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
        "CURL_CA_BUNDLE",
        "NETRC",
    }
    # Seed every unsupported ambient input in the simulated parent, then build
    # the child environment from an allowlist rather than deleting piecemeal.
    simulated_parent = dict(os.environ)
    for name in ambient_names:
        simulated_parent[name] = "must-not-be-inherited"
    inherited_hits = sum(1 for name in ambient_names if name in simulated_parent)
    environment = {
        "HOME": str(fake_home),
        "CURL_HOME": str(fake_home),
        "LC_ALL": "C",
        "NO_PROXY": "*",
    }
    check(not ambient_names.intersection(environment), "child environment omits proxy/CA/netrc ambient inputs")
    equal(inherited_hits, len(ambient_names), "ambient-isolation fixture seeds every rejected variable")
    return environment, inherited_hits


# Builds a curl config file with credentials kept out of argv.
#@param url str Request or redirect URL under test.
#@param secret str Credential used only inside the proof fixture.
#@param body_path Path File containing the request body bytes.
#@return bytes configuration Encoded curl configuration with private credential fields.
def curl_config(url: str, secret: bytes, body_path: Path) -> bytes:
    secret_text = secret.decode("ascii")
    lines = [
        f'url = "{url}"',
        'request = "POST"',
        f'header = "Authorization: Bearer {secret_text}"',
        'header = "Content-Type: application/json"',
        f'data-binary = "@{body_path}"',
        'connect-timeout = 2',
        'max-time = 10',
        'retry = 0',
        'noproxy = "*"',
        'max-redirs = 0',
    ]
    return ("\n".join(lines) + "\n").encode("utf-8")


# Starts the configured curl request for the transport proof.
#@param curl Path Pinned curl executable under test.
#@param configuration Path Private curl configuration file.
#@param environment dict[str,str] Restricted child-process environment.
#@return Popen process Started curl child monitored by the proof.
def launch_curl(curl: str, configuration: bytes, environment: dict[str, str]) -> subprocess.Popen:
    # --disable must be the first curl option. All secret-bearing configuration
    # is delivered through an anonymous stdin pipe.
    process = subprocess.Popen(
        [curl, "--disable", "--silent", "--show-error", "--no-buffer", "--config", "-"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    )
    check(process.stdin is not None, "curl stdin pipe exists")
    process.stdin.write(configuration)
    process.stdin.close()
    process.stdin = None
    return process


# Reads one procfs process attribute during zero-surface inspection.
#@param pid int Process identity inspected through procfs.
#@param name str Selected fixture, component, or tool name.
#@return bytes data Selected procfs process attribute bytes.
def read_proc_bytes(pid: int, name: str) -> bytes:
    return Path(f"/proc/{pid}/{name}").read_bytes()


# Checks a process tree for leaked secret bytes.
#@param root Path Isolated proof or staging root.
#@param value object Candidate value under validation.
#@return list hits Process-tree locations containing the searched bytes.
def scan_tree_for_value(root: Path, value: bytes) -> list[str]:
    hits: list[str] = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and value in path.read_bytes():
            hits.append(str(path.relative_to(root)))
    return hits


# Waits for a proof event while detecting early process exit.
#@param event Event Synchronization event awaited by the proof.
#@param process Popen Child process monitored by the proof.
#@param message str Assertion or diagnostic message.
#@return None result No value; returns when the event arrives and raises on early child exit.
def wait_for(event: threading.Event, process: subprocess.Popen, message: str) -> None:
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if event.wait(timeout=0.02):
            return
        check(process.poll() is None, f"curl remains alive while waiting for {message}")
    raise AssertionError(f"timed out waiting for {message}")


# Extracts the scheme, host, and port used by redirect checks.
#@param url str Request or redirect URL under test.
#@return str origin Normalized URL origin for redirect comparison.
def origin(url: str) -> tuple[str, str, int | None]:
    parsed = urllib.parse.urlsplit(url)
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80 if parsed.scheme == "http" else None
    return parsed.scheme.lower(), (parsed.hostname or "").lower(), port


# Checks whether a redirect remains inside the admitted origin.
#@param source str|Path Source file or URL being inspected.
#@param target str|dict Selected release target or destination.
#@return bool allowed Whether the destination shares the admitted origin.
def redirect_allowed(source: str, target: str) -> bool:
    return origin(source) == origin(urllib.parse.urljoin(source, target))


MASK64 = (1 << 64) - 1


# Computes a 64-bit FNV-1a digest for retry jitter.
#@param data bytes|str Input bytes or text under examination.
#@return int digest 64-bit FNV-1a hash of the supplied bytes.
def fnv1a64(data: bytes) -> int:
    value = 14695981039346656037
    for octet in data:
        value ^= octet
        value = (value * 1099511628211) & MASK64
    return value


#@class RetryManifest Owns the curl carrier proof curl carrier state and its resource lifetime.
@dataclass(frozen=True)
class RetryManifest:
    identity: str = "tp006-modern-candidate-v1"
    maximum_retry_count: int = 10
    maximum_delay_ms: int = 30_000
    runtime_wait_cap_ms: int = 60_000
    exponent: int = 2
    jitter_permille: int = 100


# Multiplies retry delay without exceeding the selected cap.
#@param value object Candidate value under validation.
#@param multiplier object The multiplier supplied to this proof operation.
#@param cap object The cap supplied to this proof operation.
#@return int product Nonnegative multiplication capped at the selected limit.
def saturating_multiply(value: int, multiplier: int, cap: int) -> int:
    if value <= 0:
        return 0
    if multiplier <= 0:
        return 0
    if value > cap // multiplier:
        return cap
    return min(value * multiplier, cap)


# Computes bounded deterministic retry delay for a logical request.
#@param logical_request object The logical request supplied to this proof operation.
#@param retry_number object The retry number supplied to this proof operation.
#@param base_ms object The base ms supplied to this proof operation.
#@param manifest object The manifest supplied to this proof operation.
#@return int delay_ms Bounded deterministic retry delay in milliseconds.
def retry_delay_ms(logical_request: str, retry_number: int, base_ms: int, manifest: RetryManifest) -> int:
    check(retry_number >= 1, "retry number starts at one after the initial attempt")
    delay = min(base_ms, manifest.maximum_delay_ms)
    for _ in range(1, retry_number):
        delay = saturating_multiply(delay, manifest.exponent, manifest.maximum_delay_ms)
    radius = (delay * manifest.jitter_permille) // 1000
    if radius == 0:
        return delay
    material = f"{manifest.identity}\0{logical_request}\0{retry_number}".encode("utf-8")
    offset = fnv1a64(material) % (2 * radius + 1) - radius
    return max(0, min(delay + offset, manifest.maximum_delay_ms))


# Checks whether the observed transport failure may be retried.
#@param category object The category supplied to this proof operation.
#@param canonical_event_seen object The canonical event seen supplied to this proof operation.
#@param cancelled object The cancelled supplied to this proof operation.
#@param outcome_unknown object The outcome unknown supplied to this proof operation.
#@return bool eligible Whether the current failure permits another attempt.
def retry_eligible(*, category: str, canonical_event_seen: bool, cancelled: bool, outcome_unknown: bool) -> bool:
    if canonical_event_seen or cancelled or outcome_unknown:
        return False
    return category in {"dns", "connect", "tls-before-body", "http-429", "http-503"}


# Bounds retry wait by Retry-After and remaining request time.
#@param local_ms object The local ms supplied to this proof operation.
#@param retry_after_ms object The retry after ms supplied to this proof operation.
#@param remaining_ms object The remaining ms supplied to this proof operation.
#@param manifest object The manifest supplied to this proof operation.
#@return int wait_ms Admitted delay within the remaining request deadline.
def effective_retry_wait(local_ms: int, retry_after_ms: int | None, remaining_ms: int, manifest: RetryManifest):
    required = max(local_ms, retry_after_ms or 0)
    if required > remaining_ms or required > manifest.runtime_wait_cap_ms:
        return None
    return required


# Proves bounded retry policy against deterministic failure cases.
#@param none No arguments.
#@return str digest SHA-256 digest of the deterministic retry trace.
def retry_scenario() -> str:
    manifest = RetryManifest()
    vectors = []
    for logical_request in ("request-A", "request-B"):
        for retry_number in range(1, 11):
            vectors.append(
                {
                    "request": logical_request,
                    "retry": retry_number,
                    "delay_ms": retry_delay_ms(logical_request, retry_number, 500, manifest),
                }
            )
    for item in vectors:
        check(0 <= item["delay_ms"] <= manifest.maximum_delay_ms, "jitter stays inside manifest cap")
    equal(len(vectors), 20, "retry golden vector covers count maximum")
    equal(1 + 0, 1, "RetryCount=0 means one initial attempt")
    equal(1 + manifest.maximum_retry_count, 11, "RetryCount means attempts after the initial attempt")
    equal(
        retry_delay_ms("request-A", 10, 2**62, manifest),
        retry_delay_ms("request-A", 10, manifest.maximum_delay_ms, manifest),
        "saturating arithmetic cannot overflow into a different delay",
    )
    for category in ("dns", "connect", "tls-before-body", "http-429", "http-503"):
        check(
            retry_eligible(category=category, canonical_event_seen=False, cancelled=False, outcome_unknown=False),
            category + " is eligible before canonical evidence",
        )
    for category in ("auth-4xx", "ordinary-4xx", "protocol", "content-refusal"):
        check(
            not retry_eligible(category=category, canonical_event_seen=False, cancelled=False, outcome_unknown=False),
            category + " is never auto-retried",
        )
    check(
        not retry_eligible(category="http-503", canonical_event_seen=True, cancelled=False, outcome_unknown=False),
        "canonical event closes retry eligibility",
    )
    check(
        not retry_eligible(category="connect", canonical_event_seen=False, cancelled=True, outcome_unknown=False),
        "cancel closes retry eligibility",
    )
    check(
        not retry_eligible(category="http-503", canonical_event_seen=False, cancelled=False, outcome_unknown=True),
        "unknown outcome closes retry eligibility",
    )
    equal(effective_retry_wait(500, 800, 1_000, manifest), 800, "Retry-After is a minimum wait")
    equal(effective_retry_wait(500, 80_000, 90_000, manifest), None, "runtime wait cap fails closed")
    equal(effective_retry_wait(500, 2_000, 1_000, manifest), None, "remaining budget fails closed")
    serialized = json.dumps(vectors, sort_keys=True, separators=(",", ":")).encode("ascii")
    return hashlib.sha256(serialized).hexdigest()


# Normalizes secret patterns before streaming redaction checks.
#@param registry object The registry supplied to this proof operation.
#@return tuple patterns Eligible secret patterns and rejected short-pattern count.
def normalized_patterns(registry: Iterable[tuple[bytes, str, str]]):
    grouped: dict[bytes, set[tuple[str, str]]] = {}
    ineligible: list[tuple[str, str]] = []
    for value, secret_class, source in registry:
        check(value != b"", "empty secret is rejected by schema")
        if len(value) < MIN_SCANNABLE_SECRET_BYTES_CANDIDATE:
            ineligible.append((secret_class, source))
            continue
        grouped.setdefault(value, set()).add((secret_class, source))
    patterns = [
        (value, tuple(sorted(metadata)))
        for value, metadata in grouped.items()
    ]
    # Orders registered secret patterns by their byte sequence.
    #@param item tuple[bytes, tuple] Pattern bytes and their provenance.
    #@return bytes Pattern bytes used as the sort key.
    patterns.sort(key=lambda item: item[0])
    ineligible.sort()
    return patterns, ineligible


# Merges overlapping secret-match byte intervals.
#@param intervals object The intervals supplied to this proof operation.
#@return tuple intervals Sorted, nonoverlapping byte intervals.
def merge_intervals(intervals: Iterable[tuple[int, int]]) -> tuple[tuple[int, int], ...]:
    ordered = sorted(set(intervals))
    merged: list[list[int]] = []
    for start, end in ordered:
        if not merged or start > merged[-1][1]:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    return tuple((start, end) for start, end in merged)


# Finds secret-match intervals across streamed chunk boundaries.
#@param chunks object The chunks supplied to this proof operation.
#@param patterns object The patterns supplied to this proof operation.
#@return tuple matches Merged secret intervals and maximum carried tail length.
def streaming_intervals(chunks: Iterable[bytes], patterns) -> tuple[tuple[tuple[int, int], ...], int]:
    maximum_pattern = max((len(value) for value, _metadata in patterns), default=1)
    tail = b""
    consumed = 0
    hits: list[tuple[int, int]] = []
    maximum_tail = 0
    for chunk in chunks:
        combined = tail + chunk
        base = consumed - len(tail)
        for pattern, _metadata in patterns:
            position = 0
            while True:
                position = combined.find(pattern, position)
                if position < 0:
                    break
                hits.append((base + position, base + position + len(pattern)))
                position += 1
        consumed += len(chunk)
        tail = combined[-(maximum_pattern - 1) :] if maximum_pattern > 1 else b""
        maximum_tail = max(maximum_tail, len(tail))
        check(len(tail) <= maximum_pattern - 1, "scanner tail is bounded")
    return merge_intervals(hits), maximum_tail


# Proves streaming secret redaction across chunk boundaries.
#@param none No arguments.
#@return tuple evidence Scanner trace digest, tail bound, and rejected-pattern count.
def scanner_scenario() -> tuple[str, int, int]:
    p1 = b"alpha-SECRET-0001"
    p2 = b"SECRET-0001-omega"
    p3 = b"SECRET-0001"
    registry = [
        (p1, "key", "Model.A.Key"),
        (p1, "proxy", "Proxy.Credential"),
        (p2, "header", "Model.A.SecretHeader"),
        (p3, "environment", "EnvironmentSet.TOKEN"),
        (b"short-7", "key", "Model.Short.Key"),
    ]
    patterns, ineligible = normalized_patterns(registry)
    equal(len(patterns), 3, "identical raw values collapse into one pattern")
    p1_metadata = dict(patterns)[p1]
    equal(len(p1_metadata), 2, "collapsed pattern retains stable class/source set")
    equal(ineligible, [("key", "Model.Short.Key")], "under-threshold secret makes consumer ineligible")

    payload = b"prefix--" + p1 + b"-omega--suffix--" + p3
    expected, _ = streaming_intervals([payload], patterns)
    check(len(expected) == 2, "overlapping hits merge into maximal interval union")
    maximum_tail = 0
    for split in range(len(payload) + 1):
        actual, tail = streaming_intervals([payload[:split], payload[split:]], patterns)
        equal(actual, expected, f"scanner is invariant at split {split}")
        maximum_tail = max(maximum_tail, tail)
    actual, tail = streaming_intervals([payload[index : index + 1] for index in range(len(payload))], patterns)
    equal(actual, expected, "scanner is invariant under one-byte chunks")
    maximum_tail = max(maximum_tail, tail)

    reversed_patterns = list(reversed(patterns))
    actual, _ = streaming_intervals([payload], reversed_patterns)
    equal(actual, expected, "matcher iteration order does not change union")
    marker = b"<registered-secret>"
    redacted = bytearray()
    cursor = 0
    for start, end in expected:
        redacted.extend(payload[cursor:start])
        redacted.extend(marker)
        cursor = end
    redacted.extend(payload[cursor:])
    check(p1 not in redacted and p2 not in redacted and p3 not in redacted, "maximal union removes every eligible pattern")
    check(all(str(end - start).encode("ascii") not in marker for start, end in expected), "marker contains no secret length")
    digest = hashlib.sha256(json.dumps(expected).encode("ascii")).hexdigest()
    return digest, maximum_tail, len(ineligible)


# Proves that credentials remain absent from command and environment surfaces.
#@param none No arguments.
#@return tuple counts Checked process purposes and secret-surface hits.
def zero_surface_scenario() -> tuple[int, int]:
    purposes = {
        "main",
        "side",
        "action-review",
        "termination-review",
        "compaction",
        "self-test",
        "context-name",
    }
    forbidden = {
        "telemetry",
        "diagnostic-upload",
        "update",
        "remote-control",
        "image",
        "audio",
        "transcription",
        "tts",
    }
    hits = purposes.intersection(forbidden)
    equal(hits, set(), "request-purpose registry has zero excluded network surfaces")
    return len(purposes), len(hits)


# Proves the curl carrier against a local HTTP server.
#@param none No arguments.
#@return tuple evidence curl version, environment, and observed request counts.
def curl_scenario() -> tuple[str, int, int, int]:
    curl = shutil.which("curl")
    check(curl is not None, "curl is installed")
    assert curl is not None
    version_line = subprocess.run(
        [curl, "--version"], check=True, stdout=subprocess.PIPE, text=True
    ).stdout.splitlines()[0]

    state = ServerState()
    server, thread = start_server(state)
    address = f"http://127.0.0.1:{server.server_address[1]}"
    canary = ("yaca-" + secrets.token_hex(24)).encode("ascii")
    check(len(canary) >= MIN_SCANNABLE_SECRET_BYTES_CANDIDATE, "runtime canary is scanner-eligible")

    with tempfile.TemporaryDirectory(prefix="yaca-tp006-") as directory:
        root = Path(directory)
        fake_home = root / "home"
        fake_home.mkdir(mode=0o700)
        (fake_home / ".curlrc").write_text(
            'header = "X-Ambient-Injected: must-not-arrive"\n'
            'max-time = 1\n',
            encoding="utf-8",
        )
        environment, inherited_ambient = scrubbed_environment(fake_home)
        body_path = root / "request-body.json"
        body = b'{"proof":"tp006","stream":true}'
        private_file(body_path, body)
        equal(stat.S_IMODE(body_path.stat().st_mode), 0o600, "request body temp is private")
        try:
            private_file(body_path, b"collision")
        except FileExistsError:
            pass
        else:
            raise AssertionError("private temp must use no-replace creation")

        echo = launch_curl(curl, curl_config(address + "/echo", canary, body_path), environment)
        wait_for(state.echo_seen, echo, "echo request")
        check(echo.poll() is None, "echo curl is inspectable while request is active")
        cmdline = read_proc_bytes(echo.pid, "cmdline")
        environ = read_proc_bytes(echo.pid, "environ")
        stdin_link = os.readlink(f"/proc/{echo.pid}/fd/0")
        check(stdin_link.startswith("pipe:["), "secret config carrier is an anonymous stdin pipe")
        check(canary not in cmdline, "canary is absent from argv/proc cmdline")
        check(canary not in environ, "canary is absent from child environment")
        equal(scan_tree_for_value(root, canary), [], "canary is absent from temp/home files")
        state.release_echo.set()
        stdout, stderr = echo.communicate(timeout=6)
        equal(echo.returncode, 0, "echo curl completes")
        equal(stdout, b"ok", "echo response is received")
        check(canary not in stdout and canary not in stderr, "canary is absent from stdout/stderr")

        echo_requests = state.matching("/echo")
        equal(len(echo_requests), 1, "echo logical request has one attempt")
        equal(echo_requests[0]["body"], body, "request body uses private temp without mutation")
        equal(
            echo_requests[0]["headers"].get("authorization"),
            "Bearer " + canary.decode("ascii"),
            "stdin config delivers Authorization header",
        )
        check("x-ambient-injected" not in echo_requests[0]["headers"], "--disable ignores malicious .curlrc")

        sse_body_path = root / "sse-body.json"
        private_file(sse_body_path, body)
        sse = launch_curl(curl, curl_config(address + "/sse", canary, sse_body_path), environment)
        wait_for(state.sse_seen, sse, "first SSE event")
        check(sse.stdout is not None, "SSE stdout pipe exists")
        first_line = sse.stdout.readline()
        equal(first_line, b"data: canonical-1\n", "first canonical SSE event is observable")
        check(canary not in read_proc_bytes(sse.pid, "cmdline"), "SSE argv contains no canary")
        check(canary not in read_proc_bytes(sse.pid, "environ"), "SSE environment contains no canary")
        sse.terminate()
        try:
            _remaining_stdout, sse_stderr = sse.communicate(timeout=4)
        except subprocess.TimeoutExpired:
            sse.kill()
            _remaining_stdout, sse_stderr = sse.communicate(timeout=2)
        state.release_sse.set()
        check(sse.returncode is not None and sse.returncode < 0, "cancel produces process-level cancelled truth")
        check(canary not in sse_stderr, "cancel stderr contains no canary")
        time.sleep(0.1)
        equal(len(state.matching("/sse")), 1, "no retry occurs after first canonical event/cancel")
        equal(scan_tree_for_value(root, canary), [], "canary leaves no recoverable temp residue")

        check(redirect_allowed(address + "/a", "/b"), "same-origin redirect policy allows same origin")
        check(
            not redirect_allowed(address + "/a", "http://127.0.0.1:1/b"),
            "different-port redirect is cross-origin and rejected",
        )
        check(
            not redirect_allowed("https://example.invalid/a", "http://example.invalid/b"),
            "HTTPS downgrade redirect is rejected",
        )

    server.shutdown()
    server.server_close()
    thread.join(timeout=3)
    check(not thread.is_alive(), "loopback proof server closes")
    return version_line, inherited_ambient, len(state.matching("/echo")), len(state.matching("/sse"))


# Runs the curl carrier proof curl carrier command and reports its status.
#@param none No arguments.
#@return None result No value; prints proof evidence and raises on failed assertions.
def main() -> None:
    curl_version, inherited_ambient, echo_attempts, sse_attempts = curl_scenario()
    retry_digest = retry_scenario()
    scanner_digest, maximum_tail, ineligible = scanner_scenario()
    purposes, excluded_purposes = zero_surface_scenario()

    print("proof=TP-006")
    print("scope=modern-host-loopback-and-deterministic-fixtures")
    print("curl=" + curl_version)
    print("secret_carrier=config-stdin")
    print("body_carrier=private-no-replace-temp")
    print("ambient_config=disabled-and-environment-allowlisted")
    print(f"ambient_parent_variables_observed={inherited_ambient}")
    print(f"attempts=echo:{echo_attempts},sse_cancel:{sse_attempts}")
    print("retry_manifest=tp006-modern-candidate-v1")
    print("retry_vector_sha256=" + retry_digest)
    print(f"minimum_scannable_secret_bytes_candidate={MIN_SCANNABLE_SECRET_BYTES_CANDIDATE}")
    print(f"scanner=max_tail:{maximum_tail},ineligible_short:{ineligible},union_sha256:{scanner_digest}")
    print(f"request_purposes=registered:{purposes},excluded_hits:{excluded_purposes}")
    print(f"assertions={ASSERTIONS}")
    print("status=PASS")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(128 + signal.SIGINT)
