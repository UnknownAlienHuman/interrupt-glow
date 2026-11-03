#!/usr/bin/env python3
"""Run the local Lua regression suite and source checks without network access."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import argparse


ROOT = Path(__file__).resolve().parents[1]
LUA_CANDIDATES = ("lua5.1", "luajit", "lua", "texlua")
NON_TEST_FILES = {"check_syntax.lua"}


def probe_lua(executable: str) -> str | None:
    """Return the language version when an executable runs Lua scripts."""
    try:
        with tempfile.TemporaryDirectory(prefix="interrupt-glow-lua-") as temp_dir:
            probe = Path(temp_dir) / "version.lua"
            probe.write_text('io.write(_VERSION, "\\n")\n', encoding="utf-8")
            result = subprocess.run(
                [executable, str(probe)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            version = result.stdout.strip()
            if result.returncode == 0 and version.startswith("Lua "):
                return version
    except OSError:
        # An explicit path may exist but be non-executable, or an interpreter
        # found on PATH may disappear before it can be probed. Treat either as
        # an unavailable runtime so the caller can report a controlled failure.
        return None
    return None


def find_lua() -> tuple[str | None, str | None]:
    """Find an installed Lua interpreter and report its language version."""
    for candidate in LUA_CANDIDATES:
        executable = shutil.which(candidate)
        if not executable:
            continue
        version = probe_lua(executable)
        if version:
            return executable, version
    return None, None


def toc_sources() -> list[Path]:
    toc_path = ROOT / "InterruptGlow.toc"
    sources: list[Path] = []
    for raw_line in toc_path.read_text(encoding="utf-8").splitlines():
        entry = raw_line.strip()
        if entry and not entry.startswith("##"):
            path = ROOT / entry
            if not path.is_file():
                raise FileNotFoundError(f"TOC source does not exist: {entry}")
            sources.append(path)
    return sources


def lua_files_to_check() -> list[Path]:
    # Keep the TOC order, then include every local Lua fixture and test by
    # discovery so a new test cannot silently escape syntax validation.
    discovered = toc_sources()
    seen = {path.resolve() for path in discovered}
    for path in sorted((ROOT / "tests").glob("*.lua")):
        if path.resolve() not in seen:
            discovered.append(path)
            seen.add(path.resolve())
    return discovered


def run(command: list[str], *, label: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)


def show_output(result: subprocess.CompletedProcess[str]) -> None:
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", help="use this Lua executable (does not fall back if invalid)")
    args = parser.parse_args()

    if args.lua:
        explicit = Path(args.lua)
        executable = str(explicit.resolve()) if explicit.is_file() else shutil.which(args.lua)
        if not executable:
            print(f"LUA TESTS SKIPPED: supplied interpreter was not found: {args.lua}", file=sys.stderr)
            return 2
        version = probe_lua(executable)
        if not version:
            print(f"LUA TESTS SKIPPED: supplied executable did not run Lua: {args.lua}", file=sys.stderr)
            return 2
    else:
        executable, version = find_lua()
    if executable is None:
        print(
            "LUA TESTS SKIPPED: no working interpreter found "
            f"(searched {', '.join(LUA_CANDIDATES)}); no packages were installed.",
            file=sys.stderr,
        )
        return 2

    print(f"Lua runtime: {executable} ({version})", flush=True)
    try:
        syntax_sources = lua_files_to_check()
    except (OSError, UnicodeError) as error:
        print(f"LUA TESTS FAILED: {error}", file=sys.stderr)
        return 1

    syntax = run(
        [executable, str(ROOT / "tests/check_syntax.lua"), *(str(path) for path in syntax_sources)],
        label="syntax",
    )
    show_output(syntax)
    if syntax.returncode:
        print(f"Lua syntax check failed (exit {syntax.returncode}).", file=sys.stderr)
        return 1

    tests = [
        path
        for path in sorted((ROOT / "tests").glob("*.lua"))
        if path.name not in NON_TEST_FILES
    ]
    passed = 0
    failed = 0
    for test in tests:
        result = run([executable, str(test), str(ROOT)], label=test.name)
        if result.returncode == 0:
            passed += 1
            output = result.stdout.strip().splitlines()
            summary = output[-1] if output else "completed without output"
            print(f"PASS {test.relative_to(ROOT)}: {summary}")
            if result.stderr.strip():
                print(result.stderr.rstrip(), file=sys.stderr)
        else:
            failed += 1
            print(f"FAIL {test.relative_to(ROOT)} (exit {result.returncode})")
            show_output(result)

    print(f"Lua regressions: {passed} passed, {failed} failed, {len(tests)} discovered")

    static = run([sys.executable, str(ROOT / "tests/static_checks.py")], label="static")
    show_output(static)
    return 1 if failed or static.returncode else 0


if __name__ == "__main__":
    raise SystemExit(main())
