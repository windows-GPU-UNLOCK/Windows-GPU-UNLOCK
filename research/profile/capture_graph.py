"""Strict diagnostic ownership snapshots shared by admission and host fixtures.

This checks the recorded format, not its provenance or hardware safety.
"""
import re

MARKER = 'gpu-console-graph-v1 observational-only; no-detach no-unlock no-nvram-write'
GUID = r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}'


def parse_handles(text):
    if len(text.encode('utf-8')) > 8 * 1024 * 1024 or text.count(MARKER) != 1:
        raise ValueError('Need one bounded diagnostic graph')
    if re.findall(r'^capture-complete=.*$', text, re.M) != ['capture-complete=1'] or \
            re.findall(r'^diagnostic-result status=.*$', text, re.M) != ['diagnostic-result status=0x0000000000000000']:
        raise ValueError('Need exactly one complete, successful diagnostic graph')
    # Presence alone does not bind a success trailer to these records. The
    # producer writes header -> graph -> completion -> caller result, while
    # ordinary handoff/transport logs may surround that frame. Ordering checks
    # only recorded syntax, not provenance or final persistence/flush success.
    starts = list(re.finditer(r'^' + re.escape(MARKER) + r'$', text, re.M))
    complete = re.search(r'^capture-complete=1$', text, re.M)
    result = re.search(r'^diagnostic-result status=0x0000000000000000$', text, re.M)
    if len(starts) != 1 or not starts[0].end() < complete.start() < result.start():
        raise ValueError('Diagnostic graph markers are out of order')
    outside = text[:starts[0].start()] + '\n' + text[complete.end():]
    # Broader separators are refusal-only here: never normalize them into
    # accepted frame boundaries. Include probe records, which the producer
    # also emits between the graph header and completion footer. Optional
    # parent-baseline observations keep their separate non-admission contract.
    structural = re.compile(r'^(?:console|variable|path|handles?|protocol|opens?|'
                            r'pci|gops?|driver|image|incomplete|cfg|mmio|probe|'
                            r'binding|img|prom)(?:[\s=-]|$)')
    if any(structural.match(line) for line in outside.splitlines()):
        raise ValueError('Graph records outside completed diagnostic frame')
    text = text[starts[0].end():complete.start()]
    headers = re.findall(r'^handles .*$', text, re.M)
    declared = re.fullmatch(r'handles status=0x([0-9a-f]{1,16}) count=0x([0-9a-f]{1,16})', headers[0]) if len(headers) == 1 else None
    if not declared or int(declared[1], 16) or not 1 <= int(declared[2], 16) <= 4096:
        raise ValueError('Incomplete handle snapshot')
    records = re.findall(r'^handle id=0x([0-9a-f]{1,16})\n(.*?)(?=^handle id=|^capture-complete=|\Z)', text, re.M | re.S)
    if len(records) != len([line for line in text.splitlines() if line.startswith('handle ')]) or len(records) != int(declared[2], 16):
        raise ValueError('Declared handle count does not match records')
    blocks = {}
    for handle, raw in records:
        h = int(handle, 16)
        if not h or h in blocks:
            raise ValueError('Null or duplicate handle record')
        prefix = raw.split('protocol guid=', 1)[0]
        if any(line.startswith('open') for line in prefix.splitlines()):
            raise ValueError('Open snapshot has no protocol')
        chunks = re.findall(r'^protocol guid=([^\n]+)\n(.*?)(?=^protocol|\Z)', raw, re.M | re.S)
        if not 1 <= len(chunks) <= 256 or len(chunks) != len([line for line in raw.splitlines() if line.startswith('protocol')]):
            raise ValueError('Missing or malformed protocol snapshot')
        protocols, edges, seen = set(), [], set()
        for protocol, detail in chunks:
            if not re.fullmatch(GUID, protocol) or protocol in protocols:
                raise ValueError('Malformed or duplicate protocol GUID')
            protocols.add(protocol)
            opens = [line for line in detail.splitlines() if line.startswith('opens')]
            rows = [line for line in detail.splitlines() if line.startswith('open') and not line.startswith('opens')]
            header = re.fullmatch(r'opens status=0x([0-9a-f]{1,16}) count=0x([0-9a-f]{1,16})', opens[0]) if len(opens) == 1 else None
            if not header or int(header[1], 16) or int(header[2], 16) > 512 or int(header[2], 16) != len(rows):
                raise ValueError('Incomplete or ambiguous open snapshot')
            for line in rows:
                row = re.fullmatch(r'open agent=0x([0-9a-f]{1,16}) controller=0x([0-9a-f]{1,16}) attributes=0x([0-9a-f]{1,16}) count=0x([0-9a-f]{1,16})', line)
                if not row:
                    raise ValueError('Malformed open record')
                agent, controller, attrs, count = (int(value, 16) for value in row.groups())
                if not 0 < attrs <= 0xffffffff or not 0 < count <= 0xffffffff or (protocol, agent, controller, attrs) in seen:
                    raise ValueError('Zero-count or duplicate open record')
                seen.add((protocol, agent, controller, attrs))
                edges.append((protocol, agent, controller, attrs, count))
        configs = re.findall(r'^pci config-dwords=.*$', raw, re.M)
        statuses = re.findall(r'^pci config-status=.*$', raw, re.M)
        if '4cf5b200-68b8-4ca5-9eec-b23e3f50029a' in protocols or configs or statuses:
            words = configs[0].split('=', 1)[1].split() if len(configs) == 1 else []
            if statuses != ['pci config-status=0x0000000000000000'] or len(words) != 16 or \
                    any(not re.fullmatch(r'[0-9a-f]{1,8}', word) for word in words):
                raise ValueError('Incomplete graph PCI configuration')
        blocks[h] = {'raw': raw, 'edges': edges, 'protocols': protocols}
    for block in blocks.values():
        for _, agent, controller, attrs, _ in block['edges']:
            if attrs not in (1, 2, 4) and (agent not in blocks or (controller and controller not in blocks)):
                raise ValueError('Unresolved active graph reference')
    return blocks
