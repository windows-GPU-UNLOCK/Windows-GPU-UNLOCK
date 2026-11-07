"""Inventory identity versus source lists only; never infer PCB or qualify hardware."""
import json
from pathlib import Path
import re
import sys


def review(inventory, envelope, source):
    if inventory.get('schema_version') != 1 or inventory.get('purpose') != 'compatibility-research-inventory':
        raise ValueError('Unexpected inventory')
    video = inventory.get('hardware', {}).get('video')
    if not isinstance(video, list) or not 1 <= len(video) <= 8:
        raise ValueError('Invalid adapter count')
    fixed = []
    for block in re.split(r'^#(?:if|elif).*$', source, flags=re.M):
        name = re.search(r'^#define GU_PROFILE_NAME "([A-Za-z0-9_-]+)"$', block, re.M)
        card = re.search(r'^#define GU_BOARD_ID 0x([0-9a-f]{8})U$', block, re.M)
        sub = re.search(r'^#define GU_BOARD_SUBSYSTEM 0x([0-9a-f]{8})U$', block, re.M)
        if name and card and sub:
            fixed.append((name[1], card[1], sub[1]))
    rows = []
    for adapter in video:
        pci = adapter.get('pci', {})
        values = [pci.get(k) for k in ['vendor', 'device', 'subsystem_vendor', 'subsystem_device']]
        if any(not isinstance(v, str) or not re.fullmatch('[0-9a-fA-F]{4}', v) for v in values):
            raise ValueError('Unknown adapter identity')
        vendor, device, subvendor, subdevice = (v.lower() for v in values)
        card = device+vendor;subsystem = subdevice+subvendor
        rows.append({'pci_dword': card, 'subsystem_dword': subsystem,
                     'generic_probe_device_listed': card in envelope['probe_device_ids'],
                     'fixed_profile_same_device': [n for n, c, s in fixed if c == card],
                     'fixed_profile_same_device_and_subsystem': [n for n, c, s in fixed if c == card and s == subsystem]})
    return {'test': 'inventory-source-scope-v1', 'adapters': rows,
            'physical_pcb_inferred_from_subsystem': False, 'machine_profile_verified': False,
            'efi_run_authorized': False, 'write_eligible': False}


if __name__ == '__main__':
    try:
        p = Path(sys.argv[1])
        if not p.is_file() or p.is_symlink() or p.stat().st_size > 1024*1024:
            raise ValueError('Input bounds')
        root = Path(__file__).resolve().parents[2]
        print(json.dumps(review(json.loads(p.read_text(encoding='utf-8-sig')),
                                json.loads((root/'research/profile/proven.json').read_text()),
                                (root/'internal-boot/unlock/machine-profile.h').read_text())))
    except Exception:
        print('Existing inventory source comparison stopped. Preserve files; no settings change or EFI run.', file=sys.stderr)
        sys.exit(1)
