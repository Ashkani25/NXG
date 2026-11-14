#!/usr/bin/env python3
"""Regenerate lib/core/assets/app_assets.dart from assets/ WITHOUT losing hand-kept code.

Run from the project root:  python3 tools/gen_assets.py [--check]

What it does
* Rewrites only the flat `static const camelName = 'assets/...';` list at the top of
  AppAssets, for the asset folders that list already covers (folders are taken
  from the current file, so new files there get constants, removed files lose them).
* Keeps EVERYTHING after that list verbatim: helper functions (portal(), disc(),
  dfTeam(), ...) and every `// ===== BEGIN ... ===== ... // ===== END ... =====`
  block, e.g. the kit_v2 game art pack block (assets/games/kit_v2/**), which games
  depend on. Those folders are owned by their block and are never added to the flat list.
* Also checks that every folder holding a referenced asset is declared in pubspec.yaml.

--check: print the diff summary and exit 1 if the file would change (no write).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DART = os.path.join(ROOT, 'lib', 'core', 'assets', 'app_assets.dart')
PUBSPEC = os.path.join(ROOT, 'pubspec.yaml')
CONST_RE = re.compile(r"^  static const ([A-Za-z0-9_]+) = '(assets/[^']+)';\s*$")
EXTS = ('.webp', '.png', '.jpg', '.jpeg', '.json', '.svg')


def camel(path):
    rel = path[len('assets/'):]
    rel = os.path.splitext(rel)[0]
    parts = re.split(r'[/_\-\s.]+', rel)
    parts = [p for p in parts if p]
    out = parts[0].lower() + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    if out[:1].isdigit():
        out = 'a' + out
    return out


def main():
    check = '--check' in sys.argv
    src = open(DART, encoding='utf-8').read().split('\n')
    head, consts, tail = [], [], []
    stage = 0
    for line in src:
        m = CONST_RE.match(line)
        if stage == 0:
            if m:
                stage = 1
                consts.append(m.groups())
            else:
                head.append(line)
        elif stage == 1:
            if m:
                consts.append(m.groups())
            else:
                stage = 2
                tail.append(line)
        else:
            tail.append(line)
    if not consts:
        sys.exit('no generated constants found; refusing to touch the file')

    # Folders owned by a BEGIN/END block are never part of the flat list.
    tail_text = '\n'.join(tail)
    owned = set()
    for block in re.findall(r'// ===== BEGIN.*?// ===== END[^\n]*', tail_text, re.S):
        for lit in re.findall(r"'(assets/[^'$]+)'", block):
            owned.add(os.path.dirname(lit))
        for top in re.findall(r'(assets/[A-Za-z0-9_/]+)/\*\*', block):
            owned.add(top)
    owned_prefixes = tuple(o + '/' for o in owned)
    folders = sorted({os.path.dirname(p) for _, p in consts})
    files = []
    for f in folders:
        d = os.path.join(ROOT, f)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            full = os.path.join(d, name)
            if os.path.isfile(full) and name.lower().endswith(EXTS):
                files.append(f + '/' + name)
    files = [p for p in files if not p.startswith(owned_prefixes)]

    seen = {}
    lines = []
    for p in sorted(set(files), key=lambda x: (os.path.dirname(x), x)):
        n = camel(p)
        if n in seen:
            sys.exit('name clash: %s for %s and %s' % (n, seen[n], p))
        seen[n] = p
        lines.append("  static const %s = '%s';" % (n, p))

    out = '\n'.join(head + lines + tail)
    old = '\n'.join(src)
    before = {n for n, _ in consts}
    added = sorted(set(seen) - before)
    removed = sorted(before - set(seen))
    print('constants: %d (added %d, removed %d); preserved tail lines: %d'
          % (len(lines), len(added), len(removed), len(tail)))
    for n in added:
        print('  + ' + n)
    for n in removed:
        print('  - ' + n)
    if 'BEGIN kit_v2' in old and 'BEGIN kit_v2' not in out:
        sys.exit('kit_v2 block would be lost; aborting')

    # pubspec folder coverage for every literal asset path in the file.
    pub = open(PUBSPEC, encoding='utf-8').read()
    declared = set(re.findall(r'^\s*-\s*(assets/\S+/)\s*$', pub, re.M))
    paths = re.findall(r"'(assets/[^'$]+\.[a-z]+)'", out)
    missing = sorted({os.path.dirname(p) + '/' for p in paths} - declared)
    for m in missing:
        print('WARNING pubspec.yaml does not declare ' + m)

    if out == old:
        print('app_assets.dart is up to date')
        return 0
    if check:
        return 1
    open(DART, 'w', encoding='utf-8').write(out)
    print('wrote ' + DART)
    return 0


if __name__ == '__main__':
    sys.exit(main())
