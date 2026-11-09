"""Check selected PE properties and file backing, not complete loader compatibility.

No image code is executed. This is not a firmware, signature or hardware test.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

def inspect(path, map_path):
    data = Path(path).read_bytes()
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    def span(at, size, message):
        require(0 <= at <= len(data) and 0 <= size <= len(data) - at, message)
    span(0, 0x40, 'truncated DOS header')
    def u16(at): return struct.unpack_from('<H', data, at)[0]
    def u32(at): return struct.unpack_from('<I', data, at)[0]
    require(data[:2] == b'MZ', 'DOS signature')
    pe = u32(0x3c)
    span(pe, 24, 'truncated PE header')
    require(data[pe:pe+4] == b'PE\0\0', 'PE signature')
    require(u16(pe+4) == 0x8664, 'must be AMD64')
    optional = pe+24
    optional_size = u16(pe+20)
    span(optional, optional_size, 'truncated optional header')
    require(optional_size >= 112 + 16*8, 'optional header cannot contain required directories')
    require(u16(optional) == 0x20b, 'must be PE32+')
    require(u16(optional+68) == 10, 'must be EFI application')
    entry = u32(optional+16)
    require(entry != 0, 'entry point missing')
    require(struct.unpack_from('<Q', data, optional+24)[0] == 0, 'expected image base 0')
    require(u16(optional+70) & 0x140 == 0x140, 'ASLR and NX flags required')
    directories = u32(optional+108)
    require(16 <= directories <= (optional_size-112)//8, 'data directory missing or outside optional header')
    for index, name in [(1, 'imports'), (12, 'IAT'), (13, 'delay imports')]:
        require(data[optional+112+8*index:optional+120+8*index] == b'\0'*8, name)
    require(u32(optional+112+8*5+4) != 0, 'relocations missing')
    table = optional+optional_size
    count = u16(pe+6)
    span(table, 40*count, 'truncated section table')
    headers = u32(optional+60)
    require(table+40*count <= headers <= len(data), 'invalid SizeOfHeaders')
    sections, raw_spans, virtual_spans = [], [], []
    for i in range(count):
        at = table+40*i
        virtual_size, rva = u32(at+8), u32(at+12)
        raw_size, raw = u32(at+16), u32(at+20)
        if raw_size:
            span(raw, raw_size, 'section raw data exceeds file')
            require(raw >= headers, 'section raw data overlaps headers')
            require(all(raw+raw_size <= lo or hi <= raw for lo, hi in raw_spans),
                    'overlapping section raw data')
            raw_spans.append((raw, raw+raw_size))
        # Zero-filled sections need no file bytes. Reject ambiguous RVA mappings,
        # including raw padding beyond VirtualSize; do not infer loader alignment.
        extent = max(virtual_size, raw_size)
        if extent:
            require(rva+extent <= 1 << 32, 'section RVA range overflow')
            require(all(rva+extent <= lo or hi <= rva for lo, hi in virtual_spans),
                    'overlapping section RVA ranges')
            virtual_spans.append((rva, rva+extent))
        sections.append((rva, virtual_size, raw_size, u32(at+36)))
    require(any(rva <= entry < rva+virtual_size and flags & 0x20000000
                and entry-rva < raw_size
                for rva, virtual_size, raw_size, flags in sections),
            'entry must be in file-backed executable section')
    reloc_rva, reloc_size = u32(optional+152), u32(optional+156)
    require(any(rva <= reloc_rva and reloc_rva-rva+reloc_size <= raw_size
                for rva, _, raw_size, _ in sections),
            'relocation directory must be file-backed')
    text = Path(map_path).read_text()
    found = re.search(r'^\s*[0-9A-Fa-f]+:[0-9A-Fa-f]+\s+efi_main\s+([0-9A-Fa-f]+)', text, re.M)
    require(found and int(found[1], 16) == entry, 'entry does not match efi_main map symbol')
    return dict(path=Path(path).name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                machine='AMD64', subsystem=10, entry='efi_main', entry_rva=entry,
                imports=0, iat=0, delay_imports=0, nx=True, dynamic_base=True)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('efi'); p.add_argument('map'); p.add_argument('--output', required=True)
    a = p.parse_args(); result = inspect(a.efi, a.map)
    Path(a.output).write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))
