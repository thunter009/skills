#!/usr/bin/env python3
"""Flag tests bucketed into a different domain PR than the source they test.

A multi-pane hunt can land as one PR per domain, assembled by bucketing every
changed file by path. Path bucketing is wrong for a test whose path prefix does
not match its subject: a five-domain hunt (2026-09) put
`frontend/lib/__tests__/api-keys-manager.test.tsx` in the API PR while the
component it asserted was in the shell PR, and only CI caught it.

For each test file in the plan, this resolves its subjects — JS/TS import,
require, and mock specifiers, or Python imports — against the plan's changed
non-test files. When no import resolves, a name-stem match (`foo.test.tsx` ->
`foo.tsx`) stands in. A test is a MISMATCH when it has a changed subject but
none in its own domain. A test with no changed subject (a test-only change)
passes.

Plan format: one `<domain><whitespace><path>` per line; `#` comments and blank
lines are ignored. Paths are repo-relative. `--root` is the hunt-tip checkout
the test files are read from; a test missing there uses the stem match only.

Exit 0 = no mismatch. Exit 1 = one or more mismatches, each with a `move` line.
Exit 2 = usage or plan error.

Usage: check_domain_pr_tests.py --plan FILE [--root DIR]
"""

from __future__ import annotations

import argparse
import posixpath
import re
import sys
from pathlib import Path

JS_EXTS = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs")
JS_TEST_RE = re.compile(r"\.(test|spec)\.[cm]?[jt]sx?$")
JS_SPEC_RE = re.compile(
    r"""(?:\bfrom\s+|\bimport\s*\(?\s*|\brequire\s*\(\s*|\.mock\s*\(\s*)['"]([^'"]+)['"]"""
)
PY_FROM_RE = re.compile(
    r"^[ \t]*from[ \t]+(\.*)([\w.]*)[ \t]+import[ \t]+(\([^)]*\)|[\w \t,*]+)", re.M
)
PY_IMPORT_RE = re.compile(r"^[ \t]*import[ \t]+([\w.]+(?:[ \t]*,[ \t]*[\w.]+)*)", re.M)


class PlanError(Exception):
    pass


def is_test(path: str) -> bool:
    name = posixpath.basename(path)
    if JS_TEST_RE.search(name):
        return True
    if "__tests__" in path.split("/")[:-1] and name.endswith(JS_EXTS):
        return True
    if re.match(r"test_.+\.(py|sh|bats)$", name):
        return True
    return bool(re.search(r".+_test\.(py|go)$", name))


def stem(path: str) -> str:
    name = posixpath.basename(path)
    name = JS_TEST_RE.sub("", name)
    name = re.sub(r"^test_", "", name)
    name = re.sub(r"_test(?=\.)", "", name)
    return name.split(".", 1)[0]


def load_plan(plan_path: str) -> dict[str, str]:
    # Any read failure must exit 2: an uncaught traceback exits 1, which reads
    # as "mismatch found".
    try:
        lines = Path(plan_path).read_text().splitlines()
    except FileNotFoundError:
        raise PlanError(f"plan not found: {plan_path}") from None
    except (OSError, UnicodeDecodeError) as exc:
        raise PlanError(f"cannot read plan {plan_path}: {exc}") from None
    plan: dict[str, str] = {}
    for lineno, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            raise PlanError(f"{plan_path}:{lineno}: want '<domain> <path>', got {raw!r}")
        domain, path = parts[0], posixpath.normpath(parts[1].strip())
        if path in plan and plan[path] != domain:
            raise PlanError(f"{plan_path}:{lineno}: {path} is in both {plan[path]} and {domain}")
        plan[path] = domain
    return plan


def js_candidates(test: str, spec: str) -> list[str]:
    """Repo-relative base paths (no extension) a JS/TS specifier may name."""
    test_dir = posixpath.dirname(test)
    if spec.startswith("."):
        return [posixpath.normpath(posixpath.join(test_dir, spec))]
    # `@/x` and `~/x` aliases, and baseUrl imports, resolve from a project
    # root somewhere above the test. Try every ancestor rather than parse
    # tsconfig paths; a bare npm package never matches a changed file.
    spec = re.sub(r"^[@~]/", "", spec)
    bases = []
    d = test_dir
    while True:
        bases.append(posixpath.normpath(posixpath.join(d, spec)))
        if not d:
            return bases
        d = posixpath.dirname(d)


def js_subjects(test: str, text: str, changed: set[str]) -> set[str]:
    found = set()
    for spec in JS_SPEC_RE.findall(text):
        for base in js_candidates(test, spec):
            for cand in [base, *(base + e for e in JS_EXTS), *(f"{base}/index{e}" for e in JS_EXTS)]:
                if cand in changed:
                    found.add(cand)
    return found


def py_modules(test: str, text: str) -> list[tuple[bool, str]]:
    """(is_relative, module path without .py) for each import in a Python file."""
    mods = []
    for dots, mod, names in PY_FROM_RE.findall(text):
        base = mod.replace(".", "/")
        if dots:
            d = posixpath.dirname(test)
            for _ in range(len(dots) - 1):
                d = posixpath.dirname(d)
            base = posixpath.normpath(posixpath.join(d, base)) if base else d
        names = [n for n in re.split(r"[\s,()]+", names) if n and n != "*"]
        mods.append((bool(dots), base))
        mods.extend((bool(dots), posixpath.join(base, n)) for n in names)
    for group in PY_IMPORT_RE.findall(text):
        mods.extend((False, m.strip().replace(".", "/")) for m in group.split(","))
    return mods


def py_subjects(test: str, text: str, changed: set[str]) -> set[str]:
    found = set()
    for relative, base in py_modules(test, text):
        for cand in (f"{base}.py", f"{base}/__init__.py"):
            # Absolute imports name a module under some source root (`src/`,
            # the repo root, ...): match those on the path suffix.
            found.update(c for c in changed if c == cand or (not relative and c.endswith("/" + cand)))
    return found


def subjects(test: str, root: Path, changed: set[str]) -> set[str]:
    try:
        text = (root / test).read_text(errors="replace")
    except OSError:
        text = ""  # deleted in the hunt; only the stem match can place it
    if test.endswith(".py"):
        found = py_subjects(test, text, changed)
    else:
        found = js_subjects(test, text, changed)
    return found or {c for c in changed if stem(c) == stem(test)}


def check(plan: dict[str, str], root: Path) -> list[tuple[str, set[str]]]:
    """(test, changed subjects) for each test with no subject in its own domain."""
    changed = {p for p in plan if not is_test(p)}
    mismatches = []
    for test in sorted(p for p in plan if is_test(p)):
        found = subjects(test, root, changed)
        if found and plan[test] not in {plan[s] for s in found}:
            mismatches.append((test, found))
    return mismatches


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plan", required=True, help="domain<TAB>path lines")
    ap.add_argument("--root", default=".", help="hunt-tip checkout (default: .)")
    args = ap.parse_args()
    try:
        plan = load_plan(args.plan)
    except PlanError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    mismatches = check(plan, Path(args.root))
    for test, found in mismatches:
        domains = sorted({plan[s] for s in found})
        where = ", ".join(f"{s} ({plan[s]})" for s in sorted(found))
        target = domains[0] if len(domains) == 1 else "|".join(domains) + " (pick one)"
        print(f"MISMATCH {test} in {plan[test]}; changed subjects: {where}")
        print(f"  move {test}: {plan[test]} -> {target}")
    tests = sum(1 for p in plan if is_test(p))
    print(f"{tests} test file(s) checked, {len(mismatches)} mismatch(es)")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
