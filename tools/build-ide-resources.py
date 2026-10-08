#!/usr/bin/env python3
"""Build src/DX.Comply.IDE.Resources.res (Win32 .res, RT_RCDATA).

The IDE package and the test program link that file from
{$R DX.Comply.IDE.Resources.res} in src/DX.Comply.IDE.Resources.pas.
That is the same pattern as src/DX.Comply.IDE.Splash.res. The
{$R file.res file.rc} line in the package source is not linked into
the BPL, so this script writes the .res that the compiler actually reads.

Run from anywhere:

    python tools/build-ide-resources.py

Inputs (paths are relative to the repository root):

    README.md
    assets/DX.Comply.Icon.bmp
    assets/DX.Comply.Icon.png

Output:

    src/DX.Comply.IDE.Resources.res

Resource names:

    DXCOMPLYREADME
    DXCOMPLYICONBMP
    DXCOMPLYICONPNG

Commit the .res after regenerating it. .gitignore ignores *.res except
this file and the splash bitmap.

The committed .res goes stale when README.md changes.
DX.Comply.Tests.IDE.ReadmeSupport.EmbeddedReadme_MatchesRepositoryFile
compares DXCOMPLYREADME with README.md at the repository root and fails
when they differ. Regenerate and commit the .res in the same change as
the README or the icon files.

src/DX.Comply.IDE.Resources.rc lists the same three files for a machine
that has brcc32. Do not also compile that script into the package.
The unit already links the .res, and a second link defines the names twice.
"""

from __future__ import annotations

import sys
from pathlib import Path

RT_RCDATA = 10
MEMORY_FLAGS = 0x0030
LANGUAGE_NEUTRAL = 0

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src" / "DX.Comply.IDE.Resources.res"
ENTRIES = (
    ("DXCOMPLYREADME", ROOT / "README.md"),
    ("DXCOMPLYICONBMP", ROOT / "assets" / "DX.Comply.Icon.bmp"),
    ("DXCOMPLYICONPNG", ROOT / "assets" / "DX.Comply.Icon.png"),
)

# First record of a Win32 .res file. DataSize 0, HeaderSize 32, type 0, name 0.
EMPTY_HEADER = bytes.fromhex(
    "0000000020000000ffff0000ffff000000000000000000000000000000000000"
)


def align4(value: int) -> int:
    return (value + 3) & ~3


def utf16z(text: str) -> bytes:
    return text.encode("utf-16le") + b"\x00\x00"


def resource_entry(name: str, payload: bytes) -> bytes:
    """One RT_RCDATA record, header and payload DWORD-aligned."""
    kind = b"\xff\xff" + RT_RCDATA.to_bytes(2, "little")
    name_bytes = utf16z(name)
    prefix_len = 8 + len(kind) + len(name_bytes)
    pad = align4(prefix_len) - prefix_len
    tail = (
        (0).to_bytes(4, "little")
        + MEMORY_FLAGS.to_bytes(2, "little")
        + LANGUAGE_NEUTRAL.to_bytes(2, "little")
        + (0).to_bytes(4, "little")
        + (0).to_bytes(4, "little")
    )
    header_size = prefix_len + pad + len(tail)
    header = (
        len(payload).to_bytes(4, "little")
        + header_size.to_bytes(4, "little")
        + kind
        + name_bytes
        + (b"\x00" * pad)
        + tail
    )
    if len(header) != header_size or header_size % 4 != 0:
        raise RuntimeError(f"header for {name} is not DWORD-aligned")
    data_pad = align4(len(payload)) - len(payload)
    return header + payload + (b"\x00" * data_pad)


def read_res_name(blob: bytes, offset: int) -> tuple[object, int]:
    if blob[offset] == 0xFF and blob[offset + 1] == 0xFF:
        value = int.from_bytes(blob[offset + 2 : offset + 4], "little")
        return value, offset + 4
    chars: list[str] = []
    while True:
        code = int.from_bytes(blob[offset : offset + 2], "little")
        offset += 2
        if code == 0:
            break
        chars.append(chr(code))
    return "".join(chars), offset


def parse_res(blob: bytes) -> list[tuple[object, object, bytes]]:
    """Return (type, name, data) for each record, including the leading empty one."""
    found: list[tuple[object, object, bytes]] = []
    offset = 0
    while offset + 8 <= len(blob):
        data_size = int.from_bytes(blob[offset : offset + 4], "little")
        header_size = int.from_bytes(blob[offset + 4 : offset + 8], "little")
        if header_size < 32 or offset + header_size > len(blob):
            raise RuntimeError(f"bad header at {offset}")
        cursor = offset + 8
        kind, cursor = read_res_name(blob, cursor)
        name, cursor = read_res_name(blob, cursor)
        data_at = offset + header_size
        data = blob[data_at : data_at + data_size]
        found.append((kind, name, data))
        offset = align4(data_at + data_size)
    if offset != len(blob):
        raise RuntimeError(f"trailing {len(blob) - offset} bytes")
    return found


def build() -> bytes:
    parts = [EMPTY_HEADER]
    for name, path in ENTRIES:
        if not path.is_file():
            raise FileNotFoundError(path)
        parts.append(resource_entry(name, path.read_bytes()))
    return b"".join(parts)


def verify(blob: bytes) -> None:
    records = parse_res(blob)
    if not records or records[0] != (0, 0, b""):
        raise RuntimeError("missing the leading empty 32-byte record")
    expected = [(name, path.read_bytes()) for name, path in ENTRIES]
    actual = records[1:]
    if len(actual) != len(expected):
        raise RuntimeError(f"expected {len(expected)} resources, found {len(actual)}")
    for (kind, name, data), (expected_name, expected_data) in zip(actual, expected):
        if kind != RT_RCDATA or name != expected_name or data != expected_data:
            raise RuntimeError(f"resource mismatch for {expected_name}")


def main() -> int:
    blob = build()
    verify(blob)
    OUTPUT.write_bytes(blob)
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({len(blob)} bytes)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - report and return non-zero
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
