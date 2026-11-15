"""Compare reported captured code against current exact card/chip envelope, offline."""
import hashlib
import json
from pathlib import Path
import re
import sys


def compare(resource, driver, envelope):
    if driver.get('Test') == 'resource-files-review-v1':
        driver = driver.get('Drivers', {})
    if driver.get('test') != 'captured-driver-review-v1' or driver.get('status') != 'observed':
        raise ValueError('Driver report unavailable')
    if any(driver.get(k) is not False for k in ['hardware_verified', 'ownership_verified', 'signature_trust_verified', 'profile_generated', 'write_eligible']):
        raise ValueError('Unexpected driver scope')
    if resource.get('HardwareVerified') is not False or resource.get('WriteEligible') is not False:
        raise ValueError('Unexpected resource scope')
    digest = driver.get('capture_sha256', '')
    markers = [m for m in resource.get('CaptureMarkers', []) if m.get('Sha256') == digest]
    if not re.fullmatch('[0-9a-f]{64}', digest) or len(markers) != 1 or markers[0].get('CompleteMarkers') != ['1'] or markers[0].get('FailedMmioReads') != 0:
        raise ValueError('Capture binding mismatch')
    observations = [o for o in resource.get('Compatibility', {}).get('observations', []) if o.get('capture') == markers[0]['Capture']]
    if len(observations) != 1 or observations[0].get('available') is not True:
        raise ValueError('Observation unavailable')
    obs = observations[0]
    cards = [c for c in obs.get('display_controllers', []) if c.get('pci_id', '').endswith('10de')]
    if len(cards) != 1 or obs.get('display_controllers_truncated') is not False:
        raise ValueError('Ambiguous card inventory')
    card = cards[0]['pci_id'];chip = obs.get('chip_id')
    families = [f for f in envelope['chips'] if f['chip'] == chip]
    if len(families) != 1 or card not in families[0].get('pci_memory', {}):
        raise ValueError('Card/chip outside envelope')
    family = families[0]
    nv = [r for r in driver.get('drivers', []) if r.get('role') == 'nvgop']
    if len(nv) != 1 or nv[0].get('status') != 'observed' or type(nv[0].get('version')) is not int or not re.fullmatch('[0-9a-f]{64}', nv[0].get('code_sha256', '')):
        raise ValueError('NVGOP observation invalid')
    nv = nv[0]
    def matches(rows):
        return any(int(r['version'], 16) == nv['version'] and r['text_sha256'] == nv['code_sha256'] for r in rows)
    global_match = matches(envelope['nvgop'])
    allowed = family.get('pci_nvgop', {}).get(card, []) if 'pci_nvgop' in family else family['nvgop']
    return {'test': 'reported-driver-envelope-v1', 'capture_sha256': digest, 'pci_id': card, 'chip_id': chip,
            'nvgop_version': hex(nv['version']), 'global_nvgop_match': global_match,
            'card_chip_nvgop_match': global_match and matches(allowed),
            'edid_global_allowlist_applicable': False,
            'status': 'code-pair-listed' if global_match and matches(allowed) else 'outside-card-code-scope',
            'reported_code_independently_rehashed': False, 'ownership_verified': False,
            'signature_trust_verified': False, 'profile_generated': False, 'write_eligible': False}


def read(path):
    p = Path(path)
    if not p.is_file() or p.is_symlink() or p.stat().st_size > 2*1024*1024:
        raise ValueError('Input bounds')
    return json.loads(p.read_text(encoding='utf-8-sig'))


if __name__ == '__main__':
    try:
        envelope_path = Path(__file__).with_name('proven.json')
        out = compare(read(sys.argv[1]), read(sys.argv[2]), read(envelope_path))
        out['envelope_sha256'] = hashlib.sha256(envelope_path.read_bytes()).hexdigest()
        print(json.dumps(out))
    except Exception:
        print('Existing report comparison stopped. Preserve files; no hardware retry or settings change.', file=sys.stderr)
        sys.exit(1)
