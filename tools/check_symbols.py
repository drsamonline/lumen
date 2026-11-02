#!/usr/bin/env python3
"""Fail if a file uses a type from lib/ that it does not import.

`flutter analyze` already catches this, but only after a push. This is the same
check locally, in a second: it finds identifiers that are declared somewhere in
lib/ and used in a file that cannot see them.

That exact mistake — using PhotoCandidate without importing models/photo.dart —
kept CI red for six releases while every other check said clean.

    python3 tools/check_symbols.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")

DECL = re.compile(
    r"^(?:abstract |final |sealed |base |const )*"
    r"(?:class|mixin|enum|extension|typedef)\s+(\w+)",
    re.M,
)
TOPDECL = re.compile(r"^(?:const |final )?(?:[\w<>?, ]+\s+)?(\w+)\s*=", re.M)
FUNC = re.compile(r"^(?:[\w<>?,\[\] ]+)\s+(\w+)\s*\(", re.M)


def declarations(path):
    """Top-level names only.

    Only column-0 lines count. Anything indented is inside a body, and matching
    those turns every local variable into a false positive.
    """
    src = open(path, encoding="utf-8").read()
    top = "\n".join(l for l in src.splitlines() if l and not l[0].isspace())
    names = set(DECL.findall(top))
    names |= set(TOPDECL.findall(top))
    names |= set(FUNC.findall(top))
    return {n for n in names if n}


def imports(path):
    src = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"^import\s+'([^']+)'", src, re.M):
        target = m.group(1)
        if target.startswith("package:lumen/"):
            out.append(os.path.join(LIB, target[len("package:lumen/"):]))
        elif not target.startswith(("dart:", "package:")):
            out.append(os.path.normpath(os.path.join(os.path.dirname(path), target)))
    return out


def strip_code(src):
    """Remove comments and string literals so identifiers inside them do not count."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
        elif c in "'\"":
            raw = i > 0 and src[i - 1] == "r"
            triple = src[i:i + 3] in ("'''", '"""')
            q = src[i:i + 3] if triple else c
            i += len(q)
            while i < n:
                if not raw and src[i] == "\\":
                    i += 2
                    continue
                if src[i:i + len(q)] == q:
                    i += len(q)
                    break
                i += 1
            out.append(" ")
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main():
    files = []
    for dp, _, ns in os.walk(LIB):
        for n in ns:
            if n.endswith(".dart"):
                files.append(os.path.join(dp, n))
    for dp, _, ns in os.walk(os.path.join(ROOT, "bin")):
        for n in ns:
            if n.endswith(".dart"):
                files.append(os.path.join(dp, n))
    for dp, _, ns in os.walk(os.path.join(ROOT, "test")):
        for n in ns:
            if n.endswith(".dart"):
                files.append(os.path.join(dp, n))

    declared = {}
    for f in files:
        declared[f] = declarations(f)

    # name -> the file that declares it
    owner = {}
    for f, names in declared.items():
        for n in names:
            owner.setdefault(n, f)

    problems = []
    for f in files:
        visible = set(declared.get(f, set()))
        for imp in imports(f):
            visible |= declared.get(imp, set())
        code = strip_code(open(f, encoding="utf-8").read())
        used = set(re.findall(r"\b([A-Z]\w+)\b", code))
        for name in used:
            home = owner.get(name)
            if home is None or home == f:
                continue
            if name in visible:
                continue
            problems.append(
                f"{os.path.relpath(f, ROOT)} uses {name} "
                f"(declared in {os.path.relpath(home, ROOT)}) without importing it"
            )

    for line in sorted(set(problems)):
        print(line)
    if problems:
        print(f"\n{len(set(problems))} missing import(s)")
        return 1
    print(f"symbols: clean across {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
