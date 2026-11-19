#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prefetch APT-resolved packages, accepting only the signed index's SHA256."""
import concurrent.futures
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

rows = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line.startswith("'https://"):
        continue
    match = re.fullmatch(r"'([^']+)' ([^/\s]+) (\d+) SHA256:([0-9a-f]{64})", line)
    if not match:
        raise SystemExit(f'Unusable package record: {line}')
    url, name, length, digest = match.groups()
    if not url.startswith('https://ports.ubuntu.com/ubuntu-ports/pool/'):
        raise SystemExit(f'Unexpected URL: {url}')
    rows.append((url, name, int(length), digest))
if not rows:
    raise SystemExit('No packages to fetch')
cache = Path(sys.argv[2])
cache.mkdir(parents=True, exist_ok=True)

def verify(path, size, digest):
    if not path.is_file() or path.stat().st_size != size:
        return False
    checksum = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            checksum.update(block)
    return checksum.hexdigest() == digest

def fetch(item):
    url, name, size, digest = item
    target = cache / name
    if verify(target, size, digest):
        return False
    partial = cache / (name + '.prefetch')
    mirror = url.replace('ports.ubuntu.com/ubuntu-ports/', 'mirrors.ustc.edu.cn/ubuntu-ports/', 1)
    urls = (url, mirror) if size > 10_000_000 or sum(name.encode()) % 2 else (mirror, url)
    for candidate in urls * 2:
        result = subprocess.run(['curl', '-fsSL', '--connect-timeout', '9', '--max-time', '360',
                                 '--speed-time', '20', '--speed-limit', '2048',
                                 candidate, '-o', str(partial)], capture_output=True)
        if result.returncode == 0 and verify(partial, size, digest):
            os.replace(partial, target)
            return True
    raise ValueError(f'Cannot fetch or verify {name}')

with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
    futures = [pool.submit(fetch, row) for row in sorted(rows, key=lambda row: row[2], reverse=True)]
    successes, failures = 0, []
    for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
        try:
            successes += future.result()
        except Exception as exc:
            failures.append(str(exc))
            print(exc, flush=True)
        if i % 40 == 0 or i == len(rows):
            print(f'{i}/{len(rows)} checked; {successes} new downloads', flush=True)
if failures:
    sys.exit(1)
