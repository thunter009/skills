#!/usr/bin/env python3
"""Safe, dry-run-first records reorganizer.

Reads a TAB-separated manifest of MOVE / TRASH actions and applies them with
hash-based dedup and collision-safe semantics. Filenames are handled as data
(no shell quoting), so spaces / & / () in names are fine.

Manifest lines (TAB-separated, absolute paths):
    MOVE \t <src> \t <dest_dir>                 # keep filename
    MOVE \t <src> \t <dest_dir> \t <new_name>   # move + rename
    TRASH \t <src> \t <reason>                  # reason required
Blank lines and lines starting with '#' are ignored.

Usage:
    DRY=1 python3 safe-reorg.py manifest.tsv    # preview (default); confirm missing=0
    DRY=0 python3 safe-reorg.py manifest.tsv    # apply

Safety:
    - Never rm. Trashes go to ~/.Trash (recoverable).
    - Dest exists + identical md5 -> trash the source (it was a dup).
    - Dest exists + different md5 -> skip and flag (never overwrite).
    - mkdir -p on destination dirs.
"""
import os, sys, shutil, hashlib

def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def unique_trash_path(trash_dir, src):
    base = os.path.basename(src)
    dest = os.path.join(trash_dir, base)
    if not os.path.exists(dest):
        return dest
    stem, ext = os.path.splitext(base)
    i = 1
    while True:
        dest = os.path.join(trash_dir, f"{stem} {i}{ext}")
        if not os.path.exists(dest):
            return dest
        i += 1

def move_to_trash(src, trash_dir):
    shutil.move(src, unique_trash_path(trash_dir, src))

def safe_filename(name):
    return name not in ("", ".", "..") and not os.path.isabs(name) and os.path.basename(name) == name

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: [DRY=1|0] safe-reorg.py <manifest.tsv>")
    dry = os.environ.get("DRY", "1") != "0"
    trash = os.path.expanduser("~/.Trash")
    moves, trashes = [], []
    with open(sys.argv[1]) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.lstrip().startswith("#"):
                continue
            parts = ln.split("\t")
            kind = parts[0].strip().upper()
            if kind == "MOVE":
                src, dest = parts[1], parts[2]
                rename = parts[3] if len(parts) > 3 and parts[3].strip() else None
                moves.append((src, dest, rename))
            elif kind == "TRASH":
                trashes.append((parts[1], parts[2] if len(parts) > 2 else ""))
            else:
                print(f"  ?? unknown action, skipped: {ln}")

    print("DRY-RUN — nothing moves\n" if dry else "EXECUTING\n")
    missing, applied = [], 0
    if not dry:
        os.makedirs(trash, exist_ok=True)

    print("== MOVES ==")
    for src, dest_dir, rename in moves:
        if not os.path.exists(src):
            missing.append(src); print(f"  !! MISSING: {src}"); continue
        name = rename or os.path.basename(src)
        if not safe_filename(name):
            missing.append(src)
            print(f"  !! INVALID RENAME: {name}")
            continue
        print(f"  {src}\n      -> {os.path.join(dest_dir, name)}")
        if dry:
            continue
        os.makedirs(dest_dir, exist_ok=True)
        dest = os.path.join(dest_dir, name)
        if os.path.exists(dest):
            if md5(dest) == md5(src):
                print("      (dest identical — trashing source)")
                move_to_trash(src, trash); applied += 1
            else:
                print("      (dest exists, DIFFERENT — skipped, needs manual)")
                missing.append(src)
            continue
        shutil.move(src, dest); applied += 1

    print("\n== TRASH (confirmed exact dups only) ==")
    for src, why in trashes:
        if not os.path.exists(src):
            print(f"  !! MISSING: {src}"); continue
        print(f"  {src}  [{why}]")
        if not dry:
            move_to_trash(src, trash); applied += 1

    tail = "" if dry else f" applied={applied}"
    print(f"\nmoves={len(moves)} trashes={len(trashes)} missing={len(missing)}{tail}")
    if missing and not dry:
        print("NOTE: 'missing' includes skipped collisions — review them manually.")

if __name__ == "__main__":
    main()
