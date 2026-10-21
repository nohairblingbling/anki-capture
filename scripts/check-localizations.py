#!/usr/bin/env python3
"""Validate translation coverage/format arguments; --write regenerates native tables."""
from pathlib import Path
import argparse
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
rows = json.loads((root / 'App/Translations.json').read_text())
languages = ['en', 'zh-Hans', 'ja']
errors = []
for key, values in rows.items():
    signature = sorted(re.findall(r'%(?:\d+\$)?(?:lld|ld|d|@)', key))
    for language in languages:
        value = values.get(language)
        if not value:
            errors.append(f'{language}: missing {key!r}')
        elif sorted(re.findall(r'%(?:\d+\$)?(?:lld|ld|d|@)', value)) != signature:
            errors.append(f'{language}: mismatched format arguments for {key!r}')
# Chinese keys are intentional legacy source keys. Runtime strings and custom
# components use these tables explicitly rather than relying on Xcode extraction.
for folder in ['CaptureApp', 'CaptureCore']:
    for path in (root / 'Sources' / folder).glob('*.swift'):
        for token in re.findall(r'"((?:[^"\\\n]|\\.)*)"', path.read_text()):
            if not re.search(r'[\u4e00-\u9fff]', token) or '\\(' in token:
                continue
            key = token.replace('\\n', '\n').replace('\\"', '"')
            if key not in rows and key not in ['简体中文', '日本語']:
                errors.append(f'{path.name}: missing source key {key!r}')
for language in languages:
    target = root / 'Sources/CaptureCore/Resources' / (language + '.lproj') / 'Localizable.strings'
    content = '// Generated from App/Translations.json.\n' + '\n'.join(
        json.dumps(k, ensure_ascii=False) + ' = ' + json.dumps(v[language], ensure_ascii=False) + ';'
        for k, v in sorted(rows.items())) + '\n'
    if args.write:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    elif not target.exists() or target.read_text() != content:
        errors.append(f'{target}: stale; run scripts/check-localizations.py --write')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'{len(rows)} keys complete in {len(languages)} languages; format arguments match.')
