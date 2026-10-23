"""Reject executable slices linked against an unexpected macOS SDK or minimum OS."""
import argparse
from pathlib import Path
import re
import subprocess
import sys


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError(f"Invalid macOS version: {value!r}")
    parts = [int(part) for part in value.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def validate_build_versions(output, sdk_version, minimum_version):
    expected_sdk = version_tuple(sdk_version)
    expected_minimum = version_tuple(minimum_version)
    slices = re.findall(r"^([^\n]+):\n(.*?)(?=^[^\n]+:\n|\Z)", output, re.MULTILINE | re.DOTALL)
    if not slices:
        raise ValueError("Missing macOS build-version metadata")
    for label, metadata in slices:
        if re.findall(r"^\s*cmd\s+(\S+)\s*$", metadata, re.MULTILINE) != ["LC_BUILD_VERSION"]:
            raise ValueError(f"Missing or ambiguous LC_BUILD_VERSION: {label}")
        fields = {}
        for key in ("platform", "minos", "sdk"):
            values = re.findall(r"^\s*" + key + r"\s+(\S+)\s*$", metadata, re.MULTILINE)
            if len(values) != 1:
                raise ValueError(f"Missing or ambiguous {key}: {label}")
            fields[key] = values[0]
        if fields["platform"] != "MACOS":
            raise ValueError(f"Unexpected build platform {fields['platform']}: {label}")
        if version_tuple(fields["sdk"]) != expected_sdk:
            raise ValueError(f"SDK mismatch: {label}: linked {fields['sdk']}, expected {sdk_version}")
        if version_tuple(fields["minos"]) != expected_minimum:
            raise ValueError(f"Minimum macOS mismatch: {label}: linked {fields['minos']}, expected {minimum_version}")
    return len(slices)


def verify_binary(binary, sdk_version, minimum_version="13.0"):
    output = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    return validate_build_versions(output, sdk_version, minimum_version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--minimum", default="13.0")
    args = parser.parse_args()
    try:
        count = verify_binary(args.binary, args.sdk, args.minimum)
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL macOS build metadata: {error}", file=sys.stderr)
        return 1
    print(f"Verified macOS SDK {args.sdk}, minimum {args.minimum}: {count} executable slice(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
