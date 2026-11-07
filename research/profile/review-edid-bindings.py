"""Existing graph relationships only; a foreign driver is not an absent driver."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('edid_graph', HERE/'make-profile.py')
mp = importlib.util.module_from_spec(spec);spec.loader.exec_module(mp)
ACTIVE = 'bd8c1056-9f36-44ec-92a8-a6337f817986'


def review(text):
    blocks = mp.parse_handles(text)
    bindings = mp.parse_bindings(text.splitlines())
    if len(blocks) > 4096 or len(bindings) > 512:
        raise ValueError('Graph bounds')
    rows = []
    for protocol in (mp.EDID_DISCOVERED, ACTIVE):
        edges = [(agent, controller, count) for block in blocks.values()
                 for p, agent, controller, attributes, count in block['edges']
                 if p == protocol and attributes == 16]
        for agent, controller, count in edges:
            owners = [b for b in bindings if b['handle'] == agent]
            if len(owners) != 1 or count != 1:
                raise ValueError('Ambiguous EDID binding')
            b = owners[0]
            file = b['file']
            identity = file[1] if file and file[0] == 'guid' else None
            rows.append({'protocol': 'discovered' if protocol == mp.EDID_DISCOVERED else 'active',
                         'version': b['version'], 'file_guid': identity,
                         'reviewed_mouse_identity_match': file == ('guid', mp.MOUSE_FILE) and b['version'] == 1})
    return {'test': 'existing-edid-bindings-v1', 'bindings': rows,
            'discovered_by_driver_count': sum(r['protocol'] == 'discovered' for r in rows),
            'active_by_driver_count': sum(r['protocol'] == 'active' for r in rows),
            'no_edid_driver_authorized': False, 'driver_detach_authorized': False,
            'post_release_binding_verified': False, 'hardware_verified': False, 'write_eligible': False}


if __name__ == '__main__':
    try:
        root = Path(sys.argv[1])
        if not root.is_dir() or root.is_symlink():
            raise ValueError('Input folder')
        paths = sorted(p for p in root.iterdir() if re.fullmatch(r'DIAG[0-9]{2}\.TXT', p.name))
        if not 1 <= len(paths) <= 16:
            raise ValueError('Capture count')
        rows = []
        for p in paths:
            if not p.is_file() or p.is_symlink() or p.stat().st_size > 4*1024*1024:
                raise ValueError('Capture bounds')
            raw = p.read_bytes();r = review(raw.decode('utf-8-sig').replace('\r\n','\n'))
            r.update(file=p.name, sha256=hashlib.sha256(raw).hexdigest());rows.append(r)
        print(json.dumps({'test': 'existing-edid-review-v1', 'captures': rows, 'write_eligible': False}))
    except Exception:
        print('Existing EDID graph review stopped. Preserve files; no new capture, flags or hardware run.', file=sys.stderr)
        sys.exit(1)
