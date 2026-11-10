"""Generate synthetic test fixtures in a new folder, never hardware evidence."""

import argparse
import json
from pathlib import Path
import struct
import sys
import tempfile

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
sys.path.insert(0, str(REPO_ROOT / 'research/profile'))


import test_local_topology as topology


def driver_image(size, rva, length, text_sha=None):
    """Create a minimal PE image for NVGOP or EDID driver inspection."""
    data = bytearray(size)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HH', data, 0x84, 0x8664, 1)
    struct.pack_into('<H', data, 0x94, 0xf0)
    struct.pack_into('<H', data, 0x98, 0x20b)
    struct.pack_into('<II', data, 0x98 + 56, size, 0x200)
    struct.pack_into('<I', data, 0x98 + 108, 16)
    struct.pack_into('<8sII', data, 0x188, b'.text', length, rva)
    struct.pack_into('<I', data, 0x188 + 36, 0x60000020)
    return data


def generate_captures(output_dir, device_id='220410de', count=2, no_edid=True):
    """Create an explicitly synthetic set without replacing an existing folder."""
    out = Path(output_dir)
    if out.exists() or out.is_symlink():
        raise FileExistsError('Choose a new synthetic-fixture folder; existing captures are never overwritten.')
    if type(count) is not int or not 1 <= count <= 32:
        raise ValueError('Synthetic capture count must be between 1 and 32.')

    board_int = int(device_id, 16)
    chip_map = {
        0x220410de: (0xb72000a1, 0x6000),  # RTX 3090 (GA102)
        0x220310de: (0xb72000a1, 0x6000),  # RTX 3090 Ti (GA102)
        0x220a10de: (0xb72000a1, 0x3000),  # RTX 3080 12GB (GA102)
        0x248210de: (0xb74000a1, 0x2000),  # RTX 3070 Ti (GA104)
        0x248410de: (0xb74000a1, 0x2000),  # RTX 3070 (GA104)
        0x24c910de: (0xb74000a1, 0x2000),  # RTX 3060 Ti (GA104)
        0x248710de: (0xb74000a1, 0x3000),  # RTX 3060 12GB (GA104)
        0x250410de: (0xb76000a1, 0x3000),  # RTX 3060 12GB (GA106)
    }

    chip, memory = chip_map.get(board_int, (0xb72000a1, 0x6000))

    text = topology.synthetic_capture(bus=1, igpu=False, no_edid=no_edid, children=2,
                                     board=board_int, chip=chip, memory=memory)

    # Insert driver bindings metadata
    first_binding = text.index('binding handle=')
    binding_count = 3 if no_edid else 4
    text = text[:first_binding] + f'driver-bindings={binding_count:08x}\n' + text[first_binding:]
    text = 'SYNTHETIC TEST FIXTURE; no hardware was observed; not unlock evidence.\n' + text

    result = {
        'purpose': 'synthetic-test-fixture',
        'hardware_tested': False,
        'write_eligible': False,
        'output_dir': str(out.resolve()),
        'captures': [f'DIAG{i:02d}.TXT' for i in range(count)],
        'images': ['IMG00.BIN'] if no_edid else ['IMG00.BIN', 'IMG01.BIN'],
        'prom': 'PROM.BIN',
        'device_id': f'{board_int:08x}',
        'chip': f'{chip:08x}',
        'memory_mib': memory,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.synthetic-fixture-', dir=out.parent) as temporary:
        stage = Path(temporary) / 'captures'
        stage.mkdir()
        for index in range(count):
            (stage / f'DIAG{index:02d}.TXT').write_text(text, encoding='ascii')
        nv_size = 0x26ae0 if board_int in (0x220310de, 0x248710de, 0x250410de) else 0x2be40
        if board_int == 0x24c910de:
            nv_size = 0x26e00
        (stage / 'IMG00.BIN').write_bytes(driver_image(nv_size, 0x280, 0x500))
        if not no_edid:
            (stage / 'IMG01.BIN').write_bytes(driver_image(0x9000, 0x1000, 0x800))
        (stage / 'PROM.BIN').write_bytes(bytes(1048576))
        (stage / 'README-SYNTHETIC.txt').write_text(
            'SYNTHETIC TEST FIXTURES ONLY\n'
            'No hardware was observed. These are not cold-boot captures, firmware dumps,\n'
            'compatibility evidence or permission to build/run an unlock.\n', encoding='ascii')
        public_metadata = {key: value for key, value in result.items() if key != 'output_dir'}
        (stage / 'SYNTHETIC-FIXTURE.json').write_text(json.dumps(public_metadata, indent=2) + '\n', encoding='utf-8')
        if out.exists() or out.is_symlink():
            raise FileExistsError('Synthetic output appeared during generation; nothing was replaced.')
        stage.rename(out)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='New output directory for synthetic test fixtures')
    parser.add_argument('--device-id', default='220410de', help='Target PCI Device ID (default: 220410de for RTX 3090)')
    parser.add_argument('--count', type=int, default=2, help='Number of synthetic records, not cold boots (1-32, default: 2)')
    parser.add_argument('--with-edid', action='store_true', help='Include EDID driver dump')
    args = parser.parse_args()

    res = generate_captures(args.output, device_id=args.device_id, count=args.count, no_edid=not args.with_edid)
    print(f"Generated SYNTHETIC TEST FIXTURES, not hardware evidence, in: {res['output_dir']}")
    print(f"  Files: {', '.join(res['captures'] + res['images'] + [res['prom']])}")


if __name__ == '__main__':
    main()

