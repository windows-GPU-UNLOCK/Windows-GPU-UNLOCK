"""Offline loaded-driver fingerprint observations, independent of profile admission."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('driver_checker', HERE / 'check-compatibility.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
mp = checker.mp


def review(folder):
    out = dict(test='captured-driver-review-v1', status='unavailable', capture_sha256=None,
               drivers=[], hardware_verified=False, ownership_verified=False,
               signature_trust_verified=False, profile_generated=False, write_eligible=False)
    try:
        names = sorted(p.name for p in folder.iterdir() if re.fullmatch(r'DIAG[0-9]{2}\.TXT', p.name))
        if not 1 <= len(names) <= 32:
            return out
        inputs = checker.Inputs(folder)
        snapshot = inputs.read(names[-1], checker.DIAG_LIMIT)
        out['capture_sha256'] = hashlib.sha256(snapshot.data).hexdigest()
        text = snapshot.data.decode('utf-8-sig').replace('\r\n', '\n')
        complete = re.findall(r'^capture-complete=.*$', text, re.M)
        if complete != ['capture-complete=1']:
            out['status'] = 'incomplete'
            return out
        bindings = mp.parse_bindings(text.splitlines())
        # Only exact known driver file identities are considered; never export paths.
        selected = [r for r in bindings if r['file'] in
                    (('name', mp.NVGOP_NAME), ('guid', mp.MOUSE_FILE))]
        if not selected or len(selected) > 16 or len({r['handle'] for r in selected}) != len(selected):
            out['status'] = 'invalid-bindings'
            return out
        envelope = json.loads((HERE / 'proven.json').read_text(encoding='utf-8'))
        checker.validate_envelope(envelope)
        for rec in selected:
            role = 'nvgop' if rec['file'][0] == 'name' else 'edid'
            row = dict(role=role, version=rec['version'], status='invalid-image',
                       code_bytes=None, code_sha256=None, listed_nvgop_code=False)
            try:
                value = mp.code_hash(inputs, rec, mp.NVGOP_TEXT_RVA if role == 'nvgop' else mp.EDID_TEXT_RVA)
                row.update(status='observed', code_bytes=value['bytes'], code_sha256=value['sha256'])
                row['listed_nvgop_code'] = role == 'nvgop' and any(
                    int(r['version'], 16) == rec['version'] and r['text_sha256'] == value['sha256']
                    for r in envelope['nvgop'])
            except FileNotFoundError:
                row['status'] = 'missing-image'
            except (OSError, ValueError, KeyError, TypeError, checker.struct.error):
                pass
            out['drivers'].append(row)
        out['status'] = 'observed'
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, checker.struct.error):
        out['status'] = 'invalid-input'
    return out


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    print(json.dumps(review(args.folder), indent=2))
