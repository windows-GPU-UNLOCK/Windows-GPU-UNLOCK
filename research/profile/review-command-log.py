"""Read supplied log text as evidence only; never execute supplied code."""
import hashlib
import json
from pathlib import Path
import re
import sys


def review(text):
    # Normalize analysis text only. The CLI hashes and preserves the original bytes.
    text = text.replace('\r\n', '\n')
    def one(pattern, convert):
        values = re.findall(pattern, text, re.M)
        if len(values) != 1:
            raise ValueError('Missing or ambiguous record')
        return convert(values[0])
    before = one(r'^\[Decode\] PCI Command before: 0x([0-9a-f]+)$', lambda x: int(x, 16))
    after = one(r'^\[Decode\] PCI Command after: 0x([0-9a-f]+) .*$', lambda x: int(x, 16))
    fields = one(r'^Transaction result=(-?\d+) safe=(\d+) retained=(\d+) started=(\d+) quiesced=(\d+) flrs=(\d+) DMA_live=(\d+)$', lambda x: [int(v) for v in x])
    if max(before, after) > 65535 or any(v not in (0, 1) for v in fields[1:6]) or not 0 <= fields[6] <= 10000000:
        raise ValueError('Out of bounds')
    restores = re.findall(r'^restore PCI command: actual=0x([0-9a-f]+) original=0x([0-9a-f]+) mask=0x([0-9a-f]+)$', text, re.M)
    if len(restores) > 1:
        raise ValueError('Ambiguous restore')
    restore = [int(v, 16) for v in restores[0]] if restores else None
    if restore and max(restore) > 65535:
        raise ValueError('Restore bounds')
    return {'test': 'existing-command-boundary-v1', 'decode_before': before, 'decode_after': after,
            'transaction': dict(zip(('result', 'safe', 'retained', 'started', 'quiesced', 'flrs', 'dma_live'), fields)),
            'restore': dict(zip(('actual', 'transaction_original', 'mask'), restore)) if restore else None,
            'transaction_original_differs_from_wrapper_entry': restore[1] != before if restore else None,
            'wrapper_entry_restoration_verified': False, 'hardware_independently_verified': False,
            'write_eligible': False, 'raw_log_exported': False}


if __name__ == '__main__':
    try:
        root = Path(sys.argv[1])
        if not root.is_dir() or root.is_symlink():
            raise ValueError('Input directory')
        rows = []
        for name in ('RUN0002-fail.TXT', 'RUN0004-ok.TXT', 'RUN0005-ok.TXT'):
            p = root / name
            if not p.is_file() or p.is_symlink() or p.stat().st_size > 1024*1024:
                raise ValueError('Input bounds')
            raw = p.read_bytes()
            row = review(raw.decode('utf-8-sig'))
            row.update(file=name, sha256=hashlib.sha256(raw).hexdigest())
            rows.append(row)
        print(json.dumps({'test': 'existing-command-boundaries-v1', 'logs': rows, 'write_eligible': False}))
    except Exception:
        print('Existing log review stopped. Preserve files; no hardware repeat or settings changes.', file=sys.stderr)
        sys.exit(1)
