"""Bounded existing-summary relationships, never hardware or release admission."""
import json
from pathlib import Path
import re
import sys

PCI = '4cf5b200-68b8-4ca5-9eec-b23e3f50029a'
GOP = '9042a9de-23dc-4a38-96fb-7aded080516a'
DEVICE_PATH = '09576e91-6d3f-11d2-8e39-00a0c969723b'


def fields(row):
    return {k: int(v, 16) for k, v in re.findall(r'([a-z-]+)=(0x[0-9a-f]{1,16})', row)}


def review(data):
    if data.get('test') != 'graph-only-v3' or data.get('hardware_verified') is not False or data.get('write_eligible') is not False:
        raise ValueError('Unexpected summary scope')
    captures = data.get('captures')
    if not isinstance(captures, list) or not 1 <= len(captures) <= 16:
        raise ValueError('Invalid capture count')
    result = {'test': 'graph-links-v1', 'captures': [], 'hardware_verified': False,
              'physical_routing_verified': False, 'release_verified': False, 'write_eligible': False}
    for capture in captures:
        digest = capture.get('sha256', '')
        if not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('Invalid capture digest')
        item = {'capture_sha256': digest, 'status': 'incomplete', 'display_adapters': [], 'gop_links': []}
        result['captures'].append(item)
        if (capture.get('graph_only_marker') is not True or capture.get('complete_markers') != ['1'] or
                capture.get('diagnostic_statuses') != ['0x0000000000000000'] or
                capture.get('incomplete_reason_count') != 0 or capture.get('unexported_reason_count') != 0):
            continue
        rows = capture.get('records')
        if not isinstance(rows, list) or len(rows) > 100000 or any(not isinstance(r, str) or len(r) > 2048 for r in rows):
            raise ValueError('Invalid record bounds')
        handles = {}; current = None; protocol = None
        for row in rows:
            if re.fullmatch(r'handle id=0x[0-9a-f]{1,16}', row):
                key = fields(row)['id']
                if key in handles:
                    raise ValueError('Duplicate handle')
                current = handles[key] = {'protocols': {}, 'gop': False}
                protocol = None
            elif re.fullmatch(r'protocol guid=[0-9a-f-]{36}', row) and current is not None:
                protocol = row.split('=')[1]
                if protocol in current['protocols']:
                    raise ValueError('Duplicate protocol')
                current['protocols'][protocol] = []
            elif current is not None and protocol is not None:
                current['protocols'][protocol].append(row)
                if protocol == GOP and row.startswith('gop framebuffer='):
                    current['gop'] = True
        displays = {}
        for key, handle in handles.items():
            pci = handle['protocols'].get(PCI, [])
            configs = [r.split('=')[1].split() for r in pci if re.fullmatch(r'pci config-dwords=(?:[0-9a-f]{8} ){15}[0-9a-f]{8}', r)]
            locations = [fields(r) for r in pci if r.startswith('pci location-status=')]
            statuses = [fields(r).get('config-status') for r in pci if r.startswith('pci config-status=')]
            if not configs:
                continue
            if len(configs) != 1 or len(locations) != 1 or statuses != [0]:
                raise ValueError('Ambiguous PCI data')
            config = configs[0]; loc = locations[0]
            if int(config[2], 16) >> 24 != 3:
                continue
            if loc.get('location-status') != 0 or set(loc) != {'location-status', 'segment', 'bus', 'device', 'function'}:
                raise ValueError('Invalid display location')
            if loc['segment'] > 65535 or loc['bus'] > 255 or loc['device'] > 31 or loc['function'] > 7:
                raise ValueError('Display location out of range')
            index = len(displays)
            displays[key] = index
            item['display_adapters'].append({'index': index, 'pci_dword': config[0], 'subsystem_dword': config[11],
                                            **{k: loc[k] for k in ['segment', 'bus', 'device', 'function']}})
        for child, handle in handles.items():
            if not handle['gop']:
                continue
            parents = set()
            path_parents = set()
            for parent, index in displays.items():
                if parent == child:
                    parents.add(index)
                for row in handles[parent]['protocols'].get(PCI, []):
                    if row.startswith('open '):
                        edge = fields(row)
                        if edge.get('controller') == child and edge.get('attributes', 0) & 8 and edge.get('count', 0) > 0:
                            parents.add(index)
                # Same agent contract as make-profile.py's sole PCI-I/O driver
                # and Device Path display-child observations. This is only a
                # graph relationship: full path/provenance/release gates remain separate.
                owners = [fields(r) for r in handles[parent]['protocols'].get(PCI, [])
                          if r.startswith('open ') and fields(r).get('attributes') == 16]
                if (len(owners) == 1 and owners[0].get('controller') == parent and
                        owners[0].get('count') == 1 and owners[0].get('agent', 0) != 0):
                    for row in handles[parent]['protocols'].get(DEVICE_PATH, []):
                        if row.startswith('open '):
                            edge = fields(row)
                            if (edge.get('controller') == child and edge.get('attributes') == 8 and
                                    edge.get('count') == 1 and edge.get('agent') == owners[0]['agent']):
                                path_parents.add(index)
            item['gop_links'].append({'status': 'unique-protocol-link' if len(parents) == 1 else 'ambiguous' if parents else 'unresolved',
                                      'candidate_adapter_indices': sorted(parents),
                                      'device_path_driver_child_status': 'unique-agent-matched-link' if len(path_parents) == 1 else 'ambiguous' if path_parents else 'unresolved',
                                      'device_path_driver_child_adapter_indices': sorted(path_parents)})
        item['status'] = 'observed'
    return result


def main():
    path = Path(sys.argv[1])
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('Input bounds')
    print(json.dumps(review(json.loads(path.read_text(encoding='utf-8-sig')))))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Existing graph relationship review stopped; preserve files and report a sanitized error.', file=sys.stderr)
        sys.exit(1)
