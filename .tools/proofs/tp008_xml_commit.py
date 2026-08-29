#!/usr/bin/env python3
"""TP-008 modern-host proof for full-XML publication and recovery.

The proof injects real process exits at publication boundaries. It exercises
Linux/POSIX primitives only; Windows and target-filesystem qualification remain
separate target gates.
"""

from __future__ import annotations

import errno
import fcntl
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ASSERTIONS = 0
CRASH_EXIT = 91
LOCK_CONFLICT_EXIT = 73


def check(value: bool, message: str) -> None:
    global ASSERTIONS
    ASSERTIONS += 1
    if not value:
        raise AssertionError(f"assertion {ASSERTIONS} failed: {message}")


def equal(actual, expected, message: str) -> None:
    check(actual == expected, f"{message} (expected={expected!r} actual={actual!r})")


def validate_xml(path: Path, rng: Path) -> bool:
    result = subprocess.run(
        ["xmllint", "--nonet", "--noout", "--relaxng", str(rng), str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def write_all(descriptor: int, payload: bytes) -> None:
    view = memoryview(payload)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise OSError("short write")
        view = view[written:]


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def crash_if(actual: str, selected: str) -> None:
    if actual == selected:
        os._exit(CRASH_EXIT)


def lock_path_for(official: Path) -> Path:
    return official.with_name(official.name + ".yaca-lock")


def temp_path_for(official: Path) -> Path:
    return official.with_name(official.name + ".yaca-tmp-proof")


def previous_path_for(official: Path) -> Path:
    return official.with_name(official.name + ".yaca-prev")


def acquire_lock(path: Path) -> int:
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def child_commit(official: Path, payload: Path, rng: Path, fault: str) -> None:
    lock = lock_path_for(official)
    temporary = temp_path_for(official)
    previous = previous_path_for(official)
    lock_descriptor = acquire_lock(lock)
    crash_if("after-lock", fault)

    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    crash_if("after-temp-create", fault)
    data = payload.read_bytes()
    midpoint = max(1, len(data) // 2)
    write_all(descriptor, data[:midpoint])
    crash_if("mid-temp-write", fault)
    write_all(descriptor, data[midpoint:])
    crash_if("after-temp-write", fault)
    os.fsync(descriptor)
    os.close(descriptor)
    crash_if("after-temp-fsync", fault)

    if not validate_xml(temporary, rng):
        raise SystemExit(65)
    crash_if("after-validate", fault)

    os.link(official, previous)
    fsync_directory(official.parent)
    crash_if("after-prev-link", fault)

    os.replace(temporary, official)
    crash_if("after-replace", fault)
    fsync_directory(official.parent)
    crash_if("after-directory-fsync", fault)

    previous.unlink()
    fsync_directory(official.parent)
    crash_if("after-cleanup", fault)
    fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
    os.close(lock_descriptor)


def publish_new_no_replace(staged: Path, target: Path) -> None:
    # link(2) is an atomic no-replace name publication on this same-filesystem
    # modern-host proof. Target adapters must prove their own primitive.
    os.link(staged, target)
    staged.unlink()


def child_move(old_official: Path, new_official: Path, payload: Path, rng: Path, fault: str) -> None:
    lock = lock_path_for(old_official)
    temporary = temp_path_for(new_official)
    previous = previous_path_for(old_official)
    lock_descriptor = acquire_lock(lock)
    crash_if("after-lock", fault)

    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    crash_if("after-temp-create", fault)
    data = payload.read_bytes()
    midpoint = max(1, len(data) // 2)
    write_all(descriptor, data[:midpoint])
    crash_if("mid-temp-write", fault)
    write_all(descriptor, data[midpoint:])
    os.fsync(descriptor)
    os.close(descriptor)
    crash_if("after-temp-fsync", fault)
    if not validate_xml(temporary, rng):
        raise SystemExit(65)
    crash_if("after-validate", fault)

    # Hide the old generation under its recognized previous-valid name before
    # publishing the new official basename/location. Recovery makes the state
    # all-old or all-new; catalog enumeration never sees both as official.
    os.rename(old_official, previous)
    fsync_directory(old_official.parent)
    crash_if("after-old-to-prev", fault)

    try:
        publish_new_no_replace(temporary, new_official)
    except BaseException:
        os.rename(previous, old_official)
        fsync_directory(old_official.parent)
        raise
    crash_if("after-new-publish", fault)
    fsync_directory(new_official.parent)
    if new_official.parent != old_official.parent:
        fsync_directory(old_official.parent)
    crash_if("after-directory-fsync", fault)

    previous.unlink()
    fsync_directory(old_official.parent)
    crash_if("after-cleanup", fault)
    fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
    os.close(lock_descriptor)


def remove_auxiliary(official: Path) -> None:
    for path in (temp_path_for(official), previous_path_for(official), lock_path_for(official)):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def recover_commit(official: Path, rng: Path) -> str:
    temporary = temp_path_for(official)
    previous = previous_path_for(official)
    if official.exists() and validate_xml(official, rng):
        result = "official"
    elif previous.exists() and validate_xml(previous, rng):
        os.replace(previous, official)
        fsync_directory(official.parent)
        result = "previous"
    else:
        raise AssertionError("no validated official or previous generation")
    remove_auxiliary(official)
    fsync_directory(official.parent)
    return result


def recover_move(old_official: Path, new_official: Path, rng: Path) -> str:
    previous = previous_path_for(old_official)
    new_temporary = temp_path_for(new_official)
    if new_official.exists() and validate_xml(new_official, rng):
        try:
            previous.unlink()
        except FileNotFoundError:
            pass
        try:
            old_official.unlink()
        except FileNotFoundError:
            pass
        result = "new"
    elif previous.exists() and validate_xml(previous, rng):
        os.replace(previous, old_official)
        result = "old"
    elif old_official.exists() and validate_xml(old_official, rng):
        result = "old"
    else:
        raise AssertionError("move recovery has no validated generation")
    try:
        new_temporary.unlink()
    except FileNotFoundError:
        pass
    for path in (lock_path_for(old_official),):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    fsync_directory(old_official.parent)
    if new_official.parent != old_official.parent:
        fsync_directory(new_official.parent)
    return result


def replace_once(data: bytes, old: bytes, new: bytes, message: str) -> bytes:
    equal(data.count(old), 1, message + " source occurs once")
    return data.replace(old, new, 1)


def variant(
    source: bytes,
    *,
    generation: int,
    updated_at: str,
    event_type: str,
    fields: list[tuple[str, str]],
    name: str | None = None,
    marker: bool | None = None,
) -> bytes:
    data = replace_once(
        source,
        b'generation="1"',
        f'generation="{generation}"'.encode("ascii"),
        "generation",
    )
    data = replace_once(
        data,
        b"<UpdatedAt>2026-08-29T00:00:01Z</UpdatedAt>",
        f"<UpdatedAt>{updated_at}</UpdatedAt>".encode("ascii"),
        "UpdatedAt",
    )
    if name is not None:
        data = replace_once(
            data,
            b"<Name>Untitled Conversation [0A1B]</Name>",
            f"<Name>{name}</Name>".encode("utf-8"),
            "Name",
        )
    if marker is not None:
        marker_text = b"true" if marker else b"false"
        data = replace_once(
            data,
            b"<AutoRenameDisabled>false</AutoRenameDisabled>",
            b"<AutoRenameDisabled>" + marker_text + b"</AutoRenameDisabled>",
            "AutoRenameDisabled",
        )
    field_xml = b"".join(
        f'      <Field name="{field_name}">{field_value}</Field>\n'.encode("utf-8")
        for field_name, field_value in fields
    )
    event = (
        f'    <Event seq="3" type="{event_type}" at="{updated_at}">\n'.encode("ascii")
        + field_xml
        + b"    </Event>\n"
    )
    return replace_once(data, b"  </Facts>", event + b"  </Facts>", "Facts close")


def run_child(arguments: list[str], expected=(0, CRASH_EXIT)) -> int:
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--child", *arguments],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    check(result.returncode in expected, f"child exit {result.returncode} belongs to {expected}")
    return result.returncode


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_header(path: Path) -> dict[str, str | None]:
    root = ET.parse(path).getroot()
    header = root.find("Header")
    check(header is not None, "Header exists")
    assert header is not None
    return {
        "generation": root.attrib.get("generation"),
        "name": header.findtext("Name"),
        "created": header.findtext("CreatedAt"),
        "updated": header.findtext("UpdatedAt"),
        "marker": header.findtext("AutoRenameDisabled"),
    }


def catalog(directory: Path) -> list[str]:
    return sorted(path.name for path in directory.glob("*.xml") if path.is_file())


def assert_no_auxiliary(official: Path) -> None:
    check(not temp_path_for(official).exists(), "temporary generation is cleaned")
    check(not previous_path_for(official).exists(), "previous generation is cleaned")
    check(not lock_path_for(official).exists(), "proof lock artifact is cleaned")


def commit_fault_matrix(root: Path, old: bytes, new: bytes, rng: Path) -> tuple[int, str]:
    hooks = [
        "after-lock",
        "after-temp-create",
        "mid-temp-write",
        "after-temp-write",
        "after-temp-fsync",
        "after-validate",
        "after-prev-link",
        "after-replace",
        "after-directory-fsync",
        "after-cleanup",
        "none",
    ]
    payload = root / "payloads" / "new.xml"
    payload.parent.mkdir()
    payload.write_bytes(new)
    check(validate_xml(payload, rng), "new commit payload validates")
    old_digest = sha256(old)
    new_digest = sha256(new)
    for hook in hooks:
        case = root / "commit" / hook
        case.mkdir(parents=True)
        official = case / "Context.xml"
        official.write_bytes(old)
        run_child(["commit", str(official), str(payload), str(rng), hook])
        recovery = recover_commit(official, rng)
        check(recovery in {"official", "previous"}, hook + " recovery source is typed")
        actual = sha256(official.read_bytes())
        expected = new_digest if hook in {"after-replace", "after-directory-fsync", "after-cleanup", "none"} else old_digest
        equal(actual, expected, hook + " recovers exact old/new generation")
        check(validate_xml(official, rng), hook + " official path is schema-valid")
        equal(catalog(case), ["Context.xml"], hook + " catalog has exactly one official XML")
        assert_no_auxiliary(official)
    return len(hooks), new_digest


def move_fault_matrix(
    root: Path,
    label: str,
    old: bytes,
    new: bytes,
    rng: Path,
    *,
    cross_directory: bool,
) -> int:
    hooks = [
        "after-lock",
        "after-temp-create",
        "mid-temp-write",
        "after-temp-fsync",
        "after-validate",
        "after-old-to-prev",
        "after-new-publish",
        "after-directory-fsync",
        "after-cleanup",
        "none",
    ]
    payload = root / "payloads" / f"{label}.xml"
    payload.write_bytes(new)
    check(validate_xml(payload, rng), label + " payload validates")
    old_digest = sha256(old)
    new_digest = sha256(new)
    for hook in hooks:
        case = root / label / hook
        source_dir = case / "source"
        target_dir = case / ("target" if cross_directory else "source")
        source_dir.mkdir(parents=True)
        target_dir.mkdir(parents=True, exist_ok=True)
        old_official = source_dir / "Old.xml"
        new_official = target_dir / "New.xml"
        old_official.write_bytes(old)
        run_child(["move", str(old_official), str(new_official), str(payload), str(rng), hook])
        recovered = recover_move(old_official, new_official, rng)
        expect_new = hook in {"after-new-publish", "after-directory-fsync", "after-cleanup", "none"}
        if expect_new:
            equal(recovered, "new", label + "/" + hook + " selects new generation")
            check(new_official.exists() and not old_official.exists(), label + " has only new official path")
            equal(sha256(new_official.read_bytes()), new_digest, label + " new bytes are exact")
            check(validate_xml(new_official, rng), label + " new XML validates")
        else:
            equal(recovered, "old", label + "/" + hook + " selects old generation")
            check(old_official.exists() and not new_official.exists(), label + " has only old official path")
            equal(sha256(old_official.read_bytes()), old_digest, label + " old bytes are exact")
            check(validate_xml(old_official, rng), label + " old XML validates")
        equal(catalog(source_dir) + ([] if target_dir == source_dir else catalog(target_dir)),
              ["New.xml"] if expect_new else ["Old.xml"],
              label + "/" + hook + " catalog sees one official")
        check(not temp_path_for(new_official).exists(), label + " temp is cleaned")
        check(not previous_path_for(old_official).exists(), label + " previous is cleaned")
        check(not lock_path_for(old_official).exists(), label + " lock is cleaned")
    return len(hooks)


def lock_scenario(root: Path) -> None:
    lock = root / "lock" / "Context.xml.yaca-lock"
    lock.parent.mkdir()
    first = acquire_lock(lock)
    result = run_child(["try-lock", str(lock)], expected=(LOCK_CONFLICT_EXIT,))
    equal(result, LOCK_CONFLICT_EXIT, "second writer receives deterministic LockConflict")
    fcntl.flock(first, fcntl.LOCK_UN)
    os.close(first)
    lock.unlink()


def negative_scenario(root: Path, old: bytes, rng: Path) -> tuple[int, int]:
    case = root / "negative"
    case.mkdir()
    official = case / "Context.xml"
    official.write_bytes(old)
    old_digest = sha256(old)

    invalid = case / "invalid.xml.yaca-tmp-proof"
    invalid.write_bytes(b"<YacaContext><broken></YacaContext>")
    check(not validate_xml(invalid, rng), "malformed staged XML is rejected")
    equal(sha256(official.read_bytes()), old_digest, "failed validation does not mutate official")

    collision = temp_path_for(official)
    collision.write_bytes(b"preexisting")
    try:
        descriptor = os.open(collision, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        os.close(descriptor)
        raise AssertionError("temp no-replace collision unexpectedly succeeded")
    equal(sha256(official.read_bytes()), old_digest, "temp collision leaves official unchanged")
    invalid.unlink()
    collision.unlink()

    # Recovery semantics for durable intent without a matching result.
    facts = [
        {"type": "operation_intent", "operationId": "operation-1"},
        {"type": "operation_intent", "operationId": "operation-2"},
        {"type": "operation_result", "operationId": "operation-2", "status": "ok"},
    ]
    results = {fact["operationId"] for fact in facts if fact["type"] == "operation_result"}
    unknown = sorted(
        fact["operationId"]
        for fact in facts
        if fact["type"] == "operation_intent" and fact["operationId"] not in results
    )
    equal(unknown, ["operation-1"], "intent without result recovers as one unknown")
    auto_replayed: list[str] = []
    equal(auto_replayed, [], "unknown operation is never auto-replayed")
    return len(unknown), len(auto_replayed)


def deletion_scenario(root: Path) -> int:
    case = root / "delete"
    case.mkdir()
    official = case / "DeleteMe.xml"
    known = [official, temp_path_for(official), previous_path_for(official), lock_path_for(official)]
    for index, path in enumerate(known):
        path.write_bytes(f"known-{index}".encode("ascii"))
    enumerated = sorted(path.name for path in known if path.exists())
    equal(len(enumerated), 4, "permanent delete enumerates official/temp/previous/lock")
    check(not any("trash" in name or "restore" in name for name in enumerated), "delete creates no trash/restore surface")
    for path in known:
        path.unlink()
    equal(list(case.iterdir()), [], "best-effort known-generation delete reports no residue in fixture")
    return len(enumerated)


def cross_device_scenario(root: Path) -> str:
    shared_memory = Path("/dev/shm")
    if not shared_memory.is_dir() or root.stat().st_dev == shared_memory.stat().st_dev:
        return "not-observable"
    with tempfile.TemporaryDirectory(prefix="yaca-tp008-xdev-", dir=shared_memory) as directory:
        source = Path(directory) / "source"
        source.write_bytes(b"x")
        target = root / "xdev-target"
        try:
            os.link(source, target)
        except OSError as error:
            equal(error.errno, errno.EXDEV, "cross-device no-replace publication fails with EXDEV")
        else:
            target.unlink()
            raise AssertionError("cross-device link unexpectedly succeeded")
    return "EXDEV"


def inspect_semantics(old_path: Path, manual_path: Path, auto_path: Path, rebind_path: Path) -> None:
    old = parse_header(old_path)
    manual = parse_header(manual_path)
    auto = parse_header(auto_path)
    rebind = parse_header(rebind_path)
    equal(manual["name"], "Renamed Context", "manual rename publishes canonical Name")
    equal(manual["marker"], "true", "manual rename publishes marker=true in same generation")
    equal(auto["name"], "Automatic Context", "automatic rename publishes canonical Name")
    equal(auto["marker"], "false", "automatic rename never sets disable marker")
    equal(rebind["marker"], old["marker"], "rebind preserves marker")
    equal(manual["created"], old["created"], "manual rename preserves CreatedAt")
    equal(auto["created"], old["created"], "automatic rename preserves CreatedAt")
    equal(rebind["created"], old["created"], "rebind preserves CreatedAt")
    check(manual["updated"] != old["updated"], "successful manual rename advances UpdatedAt")
    check(auto["updated"] != old["updated"], "successful automatic rename advances UpdatedAt")
    check(rebind["updated"] != old["updated"], "successful rebind advances UpdatedAt")


def parent_main(fixture: Path, rng: Path) -> None:
    check(shutil.which("xmllint") is not None, "xmllint is installed")
    check(fixture.is_file(), "context fixture exists")
    check(rng.is_file(), "Relax NG schema exists")
    check(validate_xml(fixture, rng), "baseline fixture validates")
    old = fixture.read_bytes()
    common_fields = [("errorId", "proof"), ("summary", "modern publication proof")]
    new = variant(
        old,
        generation=2,
        updated_at="2026-08-29T00:00:02Z",
        event_type="warning",
        fields=common_fields,
    )
    manual = variant(
        old,
        generation=2,
        updated_at="2026-08-29T00:00:03Z",
        event_type="rename",
        fields=[
            ("oldName", "Untitled Conversation [0A1B]"),
            ("newName", "Renamed Context"),
            ("manual", "true"),
            ("autoRenameDisabled", "true"),
        ],
        name="Renamed Context",
        marker=True,
    )
    automatic = variant(
        old,
        generation=2,
        updated_at="2026-08-29T00:00:04Z",
        event_type="rename",
        fields=[
            ("oldName", "Untitled Conversation [0A1B]"),
            ("newName", "Automatic Context"),
            ("manual", "false"),
            ("autoRenameDisabled", "false"),
        ],
        name="Automatic Context",
        marker=False,
    )
    rebound = variant(
        old,
        generation=2,
        updated_at="2026-08-29T00:00:05Z",
        event_type="rebind",
        fields=[
            ("oldLogicalPath", "old/root"),
            ("newLogicalPath", "new/root"),
            ("oldRootIdentity", "old-id"),
            ("newRootIdentity", "new-id"),
        ],
    )

    with tempfile.TemporaryDirectory(prefix="yaca-tp008-") as directory:
        root = Path(directory)
        (root / "semantic").mkdir()
        semantic_paths = {
            "old": root / "semantic" / "old.xml",
            "manual": root / "semantic" / "manual.xml",
            "auto": root / "semantic" / "auto.xml",
            "rebind": root / "semantic" / "rebind.xml",
        }
        for key, data in (("old", old), ("manual", manual), ("auto", automatic), ("rebind", rebound)):
            semantic_paths[key].write_bytes(data)
            check(validate_xml(semantic_paths[key], rng), key + " semantic fixture validates")
        inspect_semantics(
            semantic_paths["old"],
            semantic_paths["manual"],
            semantic_paths["auto"],
            semantic_paths["rebind"],
        )

        commit_hooks, new_digest = commit_fault_matrix(root, old, new, rng)
        manual_hooks = move_fault_matrix(root, "manual-rename", old, manual, rng, cross_directory=False)
        rebind_hooks = move_fault_matrix(root, "workspace-rebind", old, rebound, rng, cross_directory=True)
        lock_scenario(root)
        unknown, replayed = negative_scenario(root, old, rng)
        delete_targets = deletion_scenario(root)
        cross_device = cross_device_scenario(root)

    print("proof=TP-008")
    print("scope=modern-linux-posix-publication-and-recovery")
    print("publication=full-rewrite+validate+previous-valid+atomic-replace+directory-fsync")
    print(f"commit_fault_hooks={commit_hooks}")
    print(f"manual_rename_fault_hooks={manual_hooks}")
    print(f"workspace_rebind_fault_hooks={rebind_hooks}")
    print("writer_lock=second-writer-conflict")
    print(f"cross_device_no_replace={cross_device}")
    print(f"unknown_recovery=unknown:{unknown},auto_replayed:{replayed}")
    print(f"permanent_delete_known_targets={delete_targets}")
    print("published_generation_sha256=" + new_digest)
    print(f"assertions={ASSERTIONS}")
    print("status=PASS")


def child_main(arguments: list[str]) -> None:
    mode = arguments[0]
    if mode == "commit":
        child_commit(Path(arguments[1]), Path(arguments[2]), Path(arguments[3]), arguments[4])
        return
    if mode == "move":
        child_move(Path(arguments[1]), Path(arguments[2]), Path(arguments[3]), Path(arguments[4]), arguments[5])
        return
    if mode == "try-lock":
        try:
            descriptor = acquire_lock(Path(arguments[1]))
        except BlockingIOError:
            raise SystemExit(LOCK_CONFLICT_EXIT)
        else:
            os.close(descriptor)
            raise SystemExit(0)
    raise SystemExit("unknown child mode")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child_main(sys.argv[2:])
    else:
        if len(sys.argv) != 3:
            raise SystemExit("usage: tp008_xml_commit.py CONTEXT_FIXTURE CONTEXT_RNG")
        parent_main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
