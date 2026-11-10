"""Fixed B650M RAM fixtures only; no hardware capture or admission evidence."""
import re


def validate_metadata(text, config, amd, profile):
    full = re.findall(r'^cfg dwords=([^\n]+)$', text, re.M)
    graph = re.findall(r'^pci config-dwords=([^\n]+)$', text, re.M)
    if len(full) != 1 or [int(v, 16) for v in full[0].split()] != config or len(config) != 64:
        raise ValueError('Retained synthetic full configuration differs from binary input')
    if [[int(v, 16) for v in row.split()] for row in graph] != [config[:16], amd]:
        raise ValueError('Retained synthetic graph configuration differs from full input')
    bindings = profile.parse_bindings(text.splitlines())
    expected = {3: (0x2b6e0, 0x698, 0x60008), 4: (0x7820, 0x1494, 0x10),
                5: (0x48a0, 0xf04, 0x10), 9: (0x9000, 0x157c, 1)}
    if len(bindings) != len(expected) or {b['handle'] for b in bindings} != set(expected):
        raise ValueError('Retained synthetic binding inventory differs from fixed model')
    for b in bindings:
        if (b['size'], b['stop'] - b['base'], b['version']) != expected[b['handle']]:
            raise ValueError('Retained synthetic driver metadata differs from fixed model')


def capture(data, *, children, command):
    if children not in (1, 2) or command not in (2, 3):
        raise ValueError('Retained AMD model requires 1/2 children and command2/3')
    text = data.synthetic_capture(bus=1, igpu=True, no_edid=False,
                                  children=children, command=command)
    config = data.configuration(command)
    original = config.copy()
    config[11] = 0x145410de
    for words in (16, 64):
        text = text.replace(' '.join(f'{v:08x}' for v in original[:words]),
                            ' '.join(f'{v:08x}' for v in config[:words]))
    # The original fixed B650M RTX root is device1/function1, not LOCAL device3.
    text = text.replace('010106000103', '010106000101')
    amd = [0x164e1002, 2, 0x030000a1] + [0] * 13
    actual_amd = amd.copy()
    actual_amd[11] = 0x88771043
    text = text.replace(' '.join(f'{v:08x}' for v in amd),
                        ' '.join(f'{v:08x}' for v in actual_amd))
    mp = data.mp
    amd_path = bytes.fromhex('02010c00d041030a0000000001010600010801010600000002030800000301807fff0400')
    def protocol(guid, edges=(), detail=''):
        rows = ['protocol guid=' + guid,
                f'opens status=0x0000000000000000 count=0x{len(edges):x}']
        rows += [f'open agent=0x{a:x} controller=0x{c:x} attributes=0x{v:x} count=0x1'
                 for a, c, v in edges]
        return '\n'.join(rows) + '\n' + detail
    path_rows = []
    at = 0
    while at < len(amd_path):
        size = int.from_bytes(amd_path[at+2:at+4], 'little')
        path_rows.append('path-node raw=' + amd_path[at:at+size].hex())
        at += size
    block = 'handle id=0xc\n'
    block += protocol(mp.PATH, detail='\n'.join(path_rows) + '\n')
    block += protocol(mp.GOP, [(5, 12, 16)],
                      'gop framebuffer=0x000000fce0000000 bytes=0x00000000007e9000 mode=0x0 max-mode=0x9\n'
                      'gop width=0x780 height=0x438 stride=0x780\ngop pixel-format=0x0 info-bytes=0x24\n')
    block += protocol(mp.TEXT_OUT, [(4, 12, 16), (4, 6, 8)])
    block += protocol(mp.EDID_DISCOVERED, [(9, 12, 16)])
    text = text.replace('capture-complete=1\n', block + 'capture-complete=1\n')
    text = re.sub(r'(handles status=0x0000000000000000 count=0x)([0-9a-f]+)',
                  lambda m: m[1] + f'{int(m[2],16)+1:x}', text)
    # Binding metadata follows this fixed model; it never changes production pins.
    for old, new in [('0x60c0', '0x7820'), ('0x401290', '0x401494'),
                     ('0x39e0', '0x48a0'), ('0x500a3c', '0x500f04'),
                     ('0x2be40', '0x2b6e0'), ('version=0x60009', 'version=0x60008')]:
        text = text.replace(old, new)
    validate_metadata(text, config, actual_amd, mp)
    return text, config
