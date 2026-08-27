from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

START_MARKER = "-- BEGIN GENERATED INTERRUPTS_BY_SPEC"
END_MARKER = "-- END GENERATED INTERRUPTS_BY_SPEC"
SECTION_RE = re.compile(r"namespace\.InterruptSpellsBySpec\s*=\s*\{")
SPEC_RE = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{\s*(?:--\s*(.*))?$")
SOURCE_SPELL_RE = re.compile(r"^\s*(\d+)\s*,\s*(?:--\s*(.*))?$")
DATA_SPEC_RE = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{([^}]*)\}")


@dataclass(frozen=True)
class SpecInterrupts:
    spec_id: int
    spec_name: str
    spells: tuple[tuple[int, str], ...]


def extract_section(text: str) -> list[str]:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if SECTION_RE.search(line):
            start = index
            break
    if start is None:
        raise ValueError("namespace.InterruptSpellsBySpec was not found")

    depth = 0
    output: list[str] = []
    started = False
    for line in lines[start:]:
        depth += line.count("{")
        depth -= line.count("}")
        output.append(line)
        started = True
        if started and depth == 0:
            return output
    raise ValueError("unterminated InterruptSpellsBySpec table")


def parse_blizzard_source(text: str) -> list[SpecInterrupts]:
    section = extract_section(text)
    specs: list[SpecInterrupts] = []
    current_id: int | None = None
    current_name = ""
    current_spells: list[tuple[int, str]] = []

    for line in section[1:]:
        match = SPEC_RE.match(line)
        if match:
            if current_id is not None:
                raise ValueError(f"nested spec entry near {line!r}")
            current_id = int(match.group(1))
            current_name = (match.group(2) or "").strip()
            current_spells = []
            continue

        if current_id is None:
            continue

        spell_match = SOURCE_SPELL_RE.match(line)
        if spell_match:
            current_spells.append((int(spell_match.group(1)), (spell_match.group(2) or "").strip()))
            continue

        if re.match(r"^\s*},?\s*$", line):
            specs.append(SpecInterrupts(current_id, current_name, tuple(current_spells)))
            current_id = None
            current_name = ""
            current_spells = []

    if current_id is not None:
        raise ValueError(f"unterminated spec entry {current_id}")
    if not specs:
        raise ValueError("no specialization entries were parsed")
    return specs


def parse_data_block(text: str) -> dict[int, tuple[int, ...]]:
    start = text.find(START_MARKER)
    end = text.find(END_MARKER)
    if start < 0 or end < 0 or end <= start:
        raise ValueError("generated markers are missing from core/Data.lua")

    result: dict[int, tuple[int, ...]] = {}
    for line in text[start:end].splitlines():
        match = DATA_SPEC_RE.match(line)
        if not match:
            continue
        spec_id = int(match.group(1))
        ids = tuple(int(value) for value in re.findall(r"\d+", match.group(2)))
        result[spec_id] = ids
    return result


def source_mapping(specs: list[SpecInterrupts]) -> dict[int, tuple[int, ...]]:
    return {entry.spec_id: tuple(spell_id for spell_id, _ in entry.spells) for entry in specs}


def render_block(specs: list[SpecInterrupts]) -> str:
    lines = [START_MARKER, "local INTERRUPTS_BY_SPEC = {"]
    for entry in specs:
        ids = ", ".join(str(spell_id) for spell_id, _ in entry.spells)
        spell_names = ", ".join(name for _, name in entry.spells if name)
        comment_parts = [part for part in (entry.spec_name, spell_names) if part]
        comment = f" -- {': '.join(comment_parts)}" if comment_parts else ""
        lines.append(f"    [{entry.spec_id}] = {{ {ids} }},{comment}")
    lines.extend(["}", END_MARKER])
    return "\n".join(lines)


def replace_block(data_text: str, block: str) -> str:
    start = data_text.find(START_MARKER)
    end = data_text.find(END_MARKER)
    if start < 0 or end < 0 or end <= start:
        raise ValueError("generated markers are missing from core/Data.lua")
    end += len(END_MARKER)
    return data_text[:start] + block + data_text[end:]


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync Interrupt Glow's spec interrupt snapshot from Blizzard UI source")
    parser.add_argument("--source", type=Path, required=True, help="TrackedCooldowns.lua from wow-ui-source")
    parser.add_argument("--data-file", type=Path, default=Path("core/Data.lua"))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()

    specs = parse_blizzard_source(args.source.read_text(encoding="utf-8"))
    data_text = args.data_file.read_text(encoding="utf-8")

    if args.check:
        expected = source_mapping(specs)
        actual = parse_data_block(data_text)
        if actual != expected:
            print("Interrupt mapping mismatch", file=sys.stderr)
            print(f"Blizzard: {expected}", file=sys.stderr)
            print(f"Data.lua:  {actual}", file=sys.stderr)
            return 1
        print(f"Interrupt mapping matches {len(expected)} specialization entries")
        return 0

    updated = replace_block(data_text, render_block(specs))
    args.data_file.write_text(updated, encoding="utf-8")
    print(f"Updated {args.data_file} from {args.source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
