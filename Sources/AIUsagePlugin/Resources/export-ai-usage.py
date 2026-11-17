#!/usr/bin/env python3
"""Explicit statusLine bridge. Never edits provider configuration or reads account files."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import stat
import sys
import time


def number(value, minimum, maximum):
    if type(value) not in (int, float) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError("invalid quota")
    return value


def export(provider, payload):
    result = {"schema": 1, "provider": provider, "observedAt": time.time()}
    if provider == "claude":
        limits = payload["rate_limits"]
        if not isinstance(limits, dict):
            raise ValueError("quota object required")
        cleaned = {}
        for name in ("five_hour", "seven_day"):
            if name in limits:
                window = limits[name]
                cleaned[name] = {"used_percentage": number(window["used_percentage"], 0, 100),
                                 "resets_at": number(window["resets_at"], 1, 253402300799)}
        result["rate_limits"] = cleaned
    else:
        if payload["product"] != "antigravity":
            raise ValueError("wrong provider")
        if not isinstance(payload["quota"], dict):
            raise ValueError("quota object required")
        cleaned = {}
        if "gemini-weekly" in payload["quota"]:
            bucket = payload["quota"]["gemini-weekly"]
            if type(bucket.get("disabled", False)) is not bool or not isinstance(bucket["reset_time"], str):
                raise ValueError("invalid quota")
            cleaned["gemini-weekly"] = {
                "remaining_fraction": number(bucket["remaining_fraction"], 0, 1),
                "reset_time": bucket["reset_time"], "disabled": bucket.get("disabled", False)}
        result["quota"] = cleaned
        email = payload.get("email")
        if isinstance(email, str) and email.strip():
            result["accountKey"] = hashlib.sha256(("antigravity|" + email.strip().lower()).encode()).hexdigest()
    return result


def write_private(path, value):
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("absolute path required")
    # Anchor replacement to a user-owned private directory; never follow a selected link.
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    temporary = ".usage-" + secrets.token_hex(16)
    try:
        metadata = os.fstat(directory)
        if metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
            raise ValueError("private directory required")
        try:
            existing = os.stat(path.name, dir_fd=directory, follow_symlinks=False)
            if not stat.S_ISREG(existing.st_mode) or existing.st_uid != os.getuid():
                raise ValueError("regular owned file required")
        except FileNotFoundError:
            pass
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, allow_nan=False, separators=(",", ":"))
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path.name, src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        try:
            os.unlink(temporary, dir_fd=directory)
        except FileNotFoundError:
            pass
        os.close(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", required=True, choices=("claude", "antigravity"))
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    try:
        data = sys.stdin.buffer.read(1048577)
        if len(data) > 1048576:
            raise ValueError("input too large")
        payload = json.loads(data)
        if not isinstance(payload, dict):
            raise ValueError("object required")
        value = export(arguments.provider, payload)
        write_private(arguments.output, value)
    except (ValueError, TypeError, KeyError, OSError):
        # Do not log input, identity, paths, or provider error details.
        print("Usage export failed; check the quota input and private output file.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
