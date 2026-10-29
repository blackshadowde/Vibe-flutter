#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Lists the licence of every Dart package Vibe uses (from
.dart_tool/package_config.json after `flutter pub get`) and flags any that
may not be compatible with Vibe's AGPL-3.0-or-later. Prints GitHub
annotations; exits 0 (it informs, it doesn't block)."""
import json, os, re, sys
from urllib.parse import unquote, urlparse

cfg = json.load(open('.dart_tool/package_config.json'))
RULES = [  # (label, compatible with AGPL-3.0, pattern)
    ('AGPL-3.0', True, r'GNU AFFERO GENERAL PUBLIC LICENSE'),
    ('LGPL', True, r'GNU LESSER GENERAL PUBLIC LICENSE'),
    ('GPL-3.0', True, r'GNU GENERAL PUBLIC LICENSE\s+Version 3'),
    ('GPL-2.0', None, r'GNU GENERAL PUBLIC LICENSE\s+Version 2'),
    ('MPL-2.0', True, r'Mozilla Public License,? (Version|v\.?) ?2\.0'),
    ('Apache-2.0', True, r'Apache License,?\s+Version 2\.0'),
    ('BSD', True, r'Redistribution and use in source and binary forms'),
    ('MIT', True, r'Permission is hereby granted, free of charge'),
    ('ISC', True, r'Permission to use, copy, modify, and/or distribute this software'),
    ('Zlib', True, r'This software is provided .as-is., without any express'),
    ('Unlicense/0BSD', True, r'This is free and unencumbered software|Permission to use, copy, modify, and distribute this software for any purpose with or without fee'),
]
counts, flagged = {}, []
for p in cfg['packages']:
    name = p['name']
    if name == 'vibe':
        continue
    root = unquote(urlparse(p['rootUri']).path) if p['rootUri'].startswith('file:') else os.path.normpath(os.path.join('.dart_tool', p['rootUri']))
    if '/flutter/' in root and '/pub-cache/' not in root:
        label, ok = 'Flutter SDK (BSD)', True
    else:
        text = ''
        for f in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING', 'LICENCE'):
            fp = os.path.join(root, f)
            if os.path.isfile(fp):
                text = open(fp, encoding='utf-8', errors='replace').read()
                break
        label, ok = 'unknown', None
        for l, c, pat in RULES:
            if re.search(pat, text, re.I):
                label, ok = l, c
                break
        if label == 'GPL-2.0' and re.search(r'or \(at your option\) any later version', text, re.I):
            label, ok = 'GPL-2.0-or-later', True
    counts[label] = counts.get(label, 0) + 1
    if ok is not True:
        flagged.append(f'{name}: {label}')

summary = ', '.join(f'{k} {v}' for k, v in sorted(counts.items(), key=lambda x: -x[1]))
print(f'::notice title=Licences::{sum(counts.values())} packages: {summary}')
for f in flagged:
    print(f'::warning title=Licence to check::{f}')
with open(os.environ.get('GITHUB_STEP_SUMMARY', os.devnull), 'a') as s:
    s.write(f'## Licences\n\n{summary}\n\n')
    s.write(''.join(f'- check: {f}\n' for f in flagged) or 'All compatible with AGPL-3.0-or-later.\n')
