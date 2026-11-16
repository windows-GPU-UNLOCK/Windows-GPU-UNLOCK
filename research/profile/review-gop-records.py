"""Classify existing GOPDIAG text, without firmware calls or recovery advice."""
import hashlib
import json
from pathlib import Path
import re
import sys


def review(text):
    # Drop handles, framebuffer addresses and free text from the exported result.
    pattern = (r'^GOPDIAG ([A-Za-z0-9-]{1,32}): \[([0-9]{1,3})\] handle=0x[0-9a-f]+ '
               r'target=([01]) max_mode=([0-9]+) mode=([0-9]+) fb_base=(0x[0-9a-f]+|0) '
               r'fb_size=(0x[0-9a-f]+|0) hres=([0-9]+) vres=([0-9]+)$')
    rows = []
    keys = set()
    for line in text.splitlines():
        m = re.fullmatch(pattern, line)
        if not m:
            if line.startswith('GOPDIAG ') and ' max_mode=' in line:
                raise ValueError('Malformed GOP record')
            continue
        tag, index, target, maximum, current, base, size, width, height = m.groups()
        numbers = [int(x) for x in (index, maximum, current, width, height)]
        if max(numbers) > 0xffffffff or numbers[0] >= 128 or max(int(base, 0), int(size, 0)) > 0xffffffffffffffff:
            raise ValueError('GOP bounds')
        key = (tag, numbers[0])
        if key in keys:
            raise ValueError('Ambiguous GOP observation')
        keys.add(key)
        missing = int(base, 0) == 0 and int(size, 0) == 0
        partial = (int(base, 0) == 0) != (int(size, 0) == 0)
        rows.append({'phase': tag, 'index': numbers[0], 'target_reported': target == '1',
                     'mode_index_in_range': numbers[1] > 0 and numbers[2] < numbers[1],
                     'framebuffer_absent': missing, 'framebuffer_partial': partial,
                     'width': numbers[3], 'height': numbers[4],
                     'classification': 'present-without-framebuffer' if missing else 'partial-framebuffer' if partial else 'framebuffer-recorded'})
    if not rows or len(rows) > 128:
        raise ValueError('No bounded GOP observations')
    return {'test': 'existing-gop-records-v1', 'observations': rows,
            'source_text_sha256': hashlib.sha256(text.encode()).hexdigest(),
            'ancestry_independently_verified': False, 'framebuffer_geometry_verified': False,
            'set_mode_authorized': False, 'connect_controller_authorized': False,
            'hardware_independently_verified': False, 'write_eligible': False}


if __name__ == '__main__':
    try:
        p = Path(sys.argv[1])
        if not p.is_file() or p.is_symlink() or p.stat().st_size > 1024*1024:
            raise ValueError('Input bounds')
        print(json.dumps(review(p.read_text(encoding='utf-8-sig'))))
    except Exception:
        print('Existing GOP text review stopped. No new EFI, retries, SetMode or settings changes.', file=sys.stderr)
        sys.exit(1)
