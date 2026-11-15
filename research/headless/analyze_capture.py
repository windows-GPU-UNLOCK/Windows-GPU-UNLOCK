"""Offline topology research. Never authorizes unlock or accesses firmware/GPU."""
import argparse
import hashlib
import json
from pathlib import Path
import re

MARKER = 'gpu-console-graph-v1 observational-only; no-detach no-unlock no-nvram-write'
GOP = '9042a9de-23dc-4a38-96fb-7aded080516a'
TEXT = '387477c2-69c7-11d2-8e39-00a0c969723b'
INPUT = '387477c1-69c7-11d2-8e39-00a0c969723b'


def ownership_observations(records):
    """Summarize recorded opens, without inferring Driver Model authority.

    In particular attribute 0x8 is recorded literally, not relabelled as a
    BY_CHILD_CONTROLLER relationship or used to authorize a detach stage.
    """
    summary, snapshots = {}, 0
    for _, block in records:
        prefix = block.split('protocol guid=', 1)[0]
        if any(line.startswith(('opens ', 'open ')) for line in prefix.splitlines()):
            raise ValueError('Open snapshot has no protocol')
        chunks = re.findall(r'^protocol guid=([0-9a-f-]+)\n(.*?)(?=^protocol guid=|\Z)', block, re.M | re.S)
        if len(chunks) != len([line for line in block.splitlines() if line.startswith('protocol guid=')]):
            raise ValueError('Malformed protocol snapshot')
        seen = set()
        for protocol, detail in chunks:
            if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', protocol):
                raise ValueError('Malformed protocol GUID')
            if protocol in seen:
                raise ValueError('Duplicate protocol snapshot')
            seen.add(protocol)
            headers = [line for line in detail.splitlines() if line.startswith('opens ')]
            rows = [line for line in detail.splitlines() if line.startswith('open ')]
            if not headers and not rows:
                continue  # Older/minimal observational fixtures omit opens.
            header = re.fullmatch(r'opens status=0x([0-9a-f]{1,16}) count=0x([0-9a-f]{1,16})', headers[0]) if len(headers) == 1 else None
            if not header or int(header[1], 16) or int(header[2], 16) > 512 or int(header[2], 16) != len(rows):
                raise ValueError('Incomplete or ambiguous open snapshot')
            snapshots += 1
            for line in rows:
                row = re.fullmatch(r'open agent=0x([0-9a-f]{1,16}) controller=0x([0-9a-f]{1,16}) attributes=0x([0-9a-f]{1,16}) count=0x([0-9a-f]{1,16})', line)
                if not row or int(row[3], 16) > 0xffffffff or int(row[4], 16) > 0xffffffff:
                    raise ValueError('Malformed open record')
                key = (protocol, int(row[3], 16))
                item = summary.setdefault(key, {'protocol': protocol, 'attributes': f'{key[1]:x}',
                                                'records': 0, 'reported_open_count': 0})
                item['records'] += 1
                item['reported_open_count'] += int(row[4], 16)
    return {'scope': 'all recorded handles; not target-specific',
            'snapshot_count': snapshots, 'role_interpretation_performed': False,
            'attributes': [summary[key] for key in sorted(summary)]}


def device_path(block):
    # Collect declarations before validating: filtering for valid hex silently
    # drops corrupt evidence and can invent a complete path.
    rows = [line for line in block.split('\n') if line.startswith('path-node')]
    if not rows:
        return None
    nodes = []
    for row in rows:
        match = re.fullmatch(r'path-node raw=((?:[0-9a-f]{2})+)', row)
        if not match:
            raise ValueError('Malformed device path node')
        nodes.append(bytes.fromhex(match[1]))
    for i, node in enumerate(nodes):
        if len(node) < 4 or int.from_bytes(node[2:4], 'little') != len(node):
            raise ValueError('Malformed device path node')
        if node[0] == 127 and (node != b'\x7f\xff\x04\x00' or i != len(nodes)-1):
            raise ValueError('Ambiguous device path termination')
    if nodes[-1] != b'\x7f\xff\x04\x00':
        raise ValueError('Incomplete device path')
    return b''.join(nodes)


def analyze(raw, capture_index=None):
    if len(raw) > 8 * 1024 * 1024:
        raise ValueError('Capture exceeds the diagnostic format limit')
    text = raw.decode('utf-8-sig').replace('\r\n', '\n')
    sections = text.split(MARKER)[1:]
    if not sections:
        raise ValueError('No recognized graph capture')
    if capture_index is None:
        if len(sections) != 1:
            raise ValueError('Multiple captures: explicitly select --capture-index')
        capture_index = 0
    if capture_index < 0 or capture_index >= len(sections):
        raise ValueError('Capture index out of range')
    section = sections[capture_index]
    if re.findall(r'^capture-complete=.*$', section, re.M) != ['capture-complete=1']:
        raise ValueError('Incomplete or ambiguous capture')
    section = section.split('capture-complete=1\n')[0]
    consoles = re.findall(r'^console out=.*$', section, re.M)
    console = re.fullmatch(r'console out=(0x[0-9a-f]+) error=(0x[0-9a-f]+) input=(0x[0-9a-f]+)', consoles[0]) if len(consoles) == 1 else None
    if not console:
        raise ValueError('Missing system console handles')
    records = re.findall(r'^handle id=(0x[0-9a-f]+)\n(.*?)(?=^handle id=|\Z)', section, re.M | re.S)
    handles = dict(records)
    if not handles or len(handles) != len(records):
        raise ValueError('Missing or duplicate handle records')
    declared = re.search(r'^handles status=(0x[0-9a-f]+) count=(0x[0-9a-f]+)$', section, re.M)
    if not declared or int(declared[1], 16) or int(declared[2], 16) != len(handles):
        raise ValueError('Declared handle snapshot does not match records')
    if any(h not in handles for h in console.groups()):
        raise ValueError('Unresolved console handle')
    parents, pci_commands = [], []
    for h, block in records:
        configs = re.findall(r'^pci config-dwords=([^\n]*)$', block, re.M)
        statuses = re.findall(r'^pci config-status=([^\n]*)$', block, re.M)
        if not configs and not statuses:
            continue
        if len(configs) != 1 or statuses != ['0x0000000000000000']:
            raise ValueError('Incomplete or ambiguous PCI identity record')
        tokens = configs[0].split()
        if len(tokens) != 16 or any(not re.fullmatch('[0-9a-f]{1,8}', word) for word in tokens):
            raise ValueError('Incomplete PCI identity record')
        words = [int(w, 16) for w in tokens]
        path = device_path(block)
        if not path:
            raise ValueError('Missing PCI device path')
        role = 'other'
        if words[0] == 0x220410de and words[11] == 0x145410de:
            role = 'rtx3090_exact_id'
        elif words[0] == 0x164e1002 and words[11] == 0x88771043:
            role = 'amd_igpu_exact_id'
        parents.append((h, path[:-4], role))
        pci_commands.append({'role': role, 'vendor_device': f'{words[0]:08x}',
                             'subsystem': f'{words[11]:08x}',
                             'command': f'{words[1] & 0xffff:04x}',
                             'memory_enabled': bool(words[1] & 2),
                             'bus_master_enabled': bool(words[1] & 4)})
    physical, virtual = [], 0
    for h, block in records:
        if 'protocol guid=' + GOP not in block:
            continue
        modes = [line for line in block.split('\n') if line.startswith('gop framebuffer')]
        # Legacy fixtures omit the producer's mode/max-mode observation pair.
        mode = re.fullmatch(r'gop framebuffer=(0x[0-9a-f]+) bytes=(0x[0-9a-f]+)'
                            r'(?: mode=0x[0-9a-f]+ max-mode=0x[0-9a-f]+)?', modes[0]) if len(modes) == 1 else None
        if not mode:
            raise ValueError('Missing, malformed or ambiguous GOP mode record')
        fb, size = int(mode[1], 16), int(mode[2], 16)
        path = device_path(block)
        if not path and not fb and not size and h == console[1]:
            virtual += 1
            continue
        if not path or not fb or not size:
            raise ValueError('Unclassified GOP without physical geometry')
        matches = [p for p in parents if path.startswith(p[1])]
        # PCI bridges also prefix endpoint paths. Select the nearest PCI
        # ancestor, but never choose between duplicate equally deep parents.
        if matches:
            longest = max(len(p[1]) for p in matches)
            matches = [p for p in matches if len(p[1]) == longest]
        if len(matches) != 1:
            raise ValueError('GOP ancestry is unresolved or ambiguous')
        physical.append(matches[0][2])
    console_text = 'protocol guid=' + TEXT in handles[console[1]]
    input_protocol = 'protocol guid=' + INPUT in handles[console[3]]
    candidate = (physical == ['rtx3090_exact_id'] and
                 sum(p[2] == 'rtx3090_exact_id' for p in parents) == 1 and
                 console_text and input_protocol)
    return {
        'schema_version': 1,
        'input_sha256': hashlib.sha256(raw).hexdigest(),
        'capture_index': capture_index,
        'capture_count': len(sections),
        'handle_count': len(handles),
        'physical_gop_count': len(physical),
        'physical_gop_roles': physical,
        'virtual_console_gop_count': virtual,
        'system_text_output_present': console_text,
        'system_text_input_present': input_protocol,
        'single_rtx_display_topology_observed': candidate,
        'pci_command_observations': pci_commands,
        'ownership_observations': ownership_observations(records),
        'file_close_verified': False,
        'hardware_access': False,
        'authorizes_driver_detach': False,
        'authorizes_unlock': False,
        'headless_handoff_verified': False,
        'limitations': [
            'Offline parsing cannot establish capture freshness or real hardware provenance.',
            'The capture footer precedes final flush/close; it does not verify durable storage, cleanup or Windows handoff.',
            'Only PCI identity/path topology is classified; driver code, ownership safety, PROM, input liveness and Windows behavior are not validated.',
            'An installed iGPU with no active GOP is not equivalent evidence to a CPU without an iGPU.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--capture-index', type=int)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        with args.capture.open('rb') as stream:
            raw = stream.read(8 * 1024 * 1024 + 1)
        result = analyze(raw, args.capture_index)
        text = json.dumps(result, indent=2) + '\n'
        if args.output:
            # Explicit new local output only: never replace previous evidence.
            with args.output.open('x', encoding='utf-8', newline='\n') as stream:
                stream.write(text)
        else:
            print(text, end='')
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(2, 'Capture rejected: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
