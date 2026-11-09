"""Constructed PE bytes only: no compiler, firmware, image execution or hardware."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ('unlock/verify_pe.py', 'internal-boot/unlock/verify_pe.py')


def image():
    data = bytearray(0x600)
    data[:2] = b'MZ'
    def u16(at, value): struct.pack_into('<H', data, at, value)
    def u32(at, value): struct.pack_into('<I', data, at, value)
    u32(0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    u16(0x84, 0x8664); u16(0x86, 2); u16(0x94, 0xf0); u16(0x96, 0x22)
    optional = 0x98
    u16(optional, 0x20b); u32(optional+16, 0x1000); u32(optional+20, 0x1000)
    u32(optional+32, 0x1000); u32(optional+36, 0x200)
    u32(optional+56, 0x3000); u32(optional+60, 0x200)
    u16(optional+68, 10); u16(optional+70, 0x140); u32(optional+108, 16)
    u32(optional+152, 0x2000); u32(optional+156, 12)
    for at, name, rva, size, raw, flags in (
            (0x188, b'.text', 0x1000, 0x200, 0x200, 0x60000020),
            (0x1b0, b'.reloc', 0x2000, 12, 0x400, 0x42000040)):
        data[at:at+len(name)] = name
        u32(at+8, size); u32(at+12, rva); u32(at+16, 0x200)
        u32(at+20, raw); u32(at+36, flags)
    u32(0x400, 0x1000); u32(0x404, 12)
    return data


class FileBoundsTests(unittest.TestCase):
    def inspect_both(self, data, accepted=False, entry=0x1000):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, link_map = root/'synthetic.bin', root/'synthetic.map'
            binary.write_bytes(data)
            link_map.write_text(f' 0001:00000000 efi_main {entry:016x}\n')
            for source in SOURCES:
                with self.subTest(source=source):
                    spec = importlib.util.spec_from_file_location('verifier', ROOT/source)
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                    if accepted:
                        result = module.inspect(binary, link_map)
                        self.assertEqual(result['bytes'], len(data))
                    else:
                        with self.assertRaises(ValueError):
                            module.inspect(binary, link_map)

    def test_complete_and_exact_eof(self):
        self.inspect_both(image(), accepted=True)

    def test_truncated_raw_sections(self):
        for end in (0x200, 0x3ff, 0x400, 0x5ff):
            with self.subTest(end=end): self.inspect_both(image()[:end])

    def test_truncated_headers(self):
        for end in (0, 2, 0x3f, 0x83, 0x97, 0x187, 0x1d7):
            with self.subTest(end=end): self.inspect_both(image()[:end])

    def test_bad_header_extents(self):
        for at, fmt, value in ((0x94, '<H', 0x70), (0x94, '<H', 0xffff),
                               (0x98+60, '<I', 0x100), (0x98+60, '<I', 0x601),
                               (0x98+108, '<I', 0xffffffff)):
            data=image(); struct.pack_into(fmt, data, at, value)
            with self.subTest(at=at, value=value): self.inspect_both(data)

    def test_raw_offsets_sizes_and_overlap(self):
        for at, value in ((0x188+20, 0xfffffff0), (0x188+16, 0xffffffff),
                          (0x188+20, 0x100), (0x1b0+20, 0x200)):
            data=image(); struct.pack_into('<I', data, at, value)
            with self.subTest(at=at, value=value): self.inspect_both(data)

    def test_entry_in_zero_filled_tail(self):
        data=image(); struct.pack_into('<I',data,0x188+8,0x400)
        struct.pack_into('<I',data,0x98+16,0x1200)
        self.inspect_both(data, entry=0x1200)

    def test_virtual_overlap(self):
        data=image(); struct.pack_into('<I',data,0x1b0+12,0x1000)
        self.inspect_both(data)

    def test_unbacked_relocations(self):
        for rva, size in ((0,12), (0x3000,12), (0x21fc,12), (0xfffffff0,32)):
            data=image(); struct.pack_into('<II',data,0x98+152,rva,size)
            with self.subTest(rva=rva,size=size): self.inspect_both(data)

    def test_zero_filled_nonentry_section_is_allowed(self):
        # Add BSS without imposing a file-backing requirement on zero fill.
        data=image(); struct.pack_into('<H',data,0x86,3)
        data[0x1d8:0x1dc]=b'.bss'
        struct.pack_into('<II',data,0x1d8+8,0x1000,0x3000)
        struct.pack_into('<I',data,0x1d8+36,0xc0000080)
        struct.pack_into('<I',data,0x98+56,0x4000)
        self.inspect_both(data, accepted=True)

    def test_optimized_cli_does_not_write_success_for_truncation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, link_map = root/'synthetic.bin', root/'synthetic.map'
            link_map.write_text(' 0001:00000000 efi_main 0000000000001000\n')
            for index, source in enumerate(SOURCES):
                for accepted, data in ((True, image()), (False, image()[:0x200])):
                    output = root/f'report-{index}-{accepted}.json'
                    binary.write_bytes(data)
                    result = subprocess.run([sys.executable, '-O', str(ROOT/source),
                        str(binary), str(link_map), '--output', str(output)],
                        capture_output=True, text=True, timeout=10)
                    with self.subTest(source=source, accepted=accepted):
                        self.assertEqual(result.returncode == 0, accepted)
                        self.assertEqual(output.exists(), accepted)

    def test_raw_padding_can_exceed_virtual_size(self):
        data=image(); struct.pack_into('<I',data,0x188+8,1)
        self.inspect_both(data, accepted=True)

    def test_zero_virtual_size_nonentry_section(self):
        data=image(); struct.pack_into('<I',data,0x1b0+8,0)
        self.inspect_both(data, accepted=True)

    def test_relocation_exact_raw_end_and_one_byte_over(self):
        for size in (12, 13):
            data=image(); struct.pack_into('<II',data,0x98+152,0x21f4,size)
            with self.subTest(size=size):
                self.inspect_both(data, accepted=size == 12)

    def test_section_rva_overflow(self):
        data=image(); struct.pack_into('<I',data,0x1b0+12,0xfffffff0)
        self.inspect_both(data)

    def test_invalid_cli_preserves_previous_output(self):
        # A nonzero status invalidates this attempt, not an earlier receipt.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, link_map = root/'synthetic.bin', root/'synthetic.map'
            binary.write_bytes(image()[:0x200])
            link_map.write_text(' 0001:00000000 efi_main 0000000000001000\n')
            previous = b'previous report must remain unchanged\n'
            for source in SOURCES:
                output = root/'previous.json'
                output.write_bytes(previous)
                result = subprocess.run([sys.executable, '-O', str(ROOT/source),
                    str(binary), str(link_map), '--output', str(output)],
                    capture_output=True, text=True, timeout=10)
                with self.subTest(source=source):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_bytes(), previous)

    def test_existing_policy_checks_remain(self):
        for at, fmt, value in ((0x84,'<H',0x14c),(0x98+68,'<H',3),
                (0x98+70,'<H',0),(0x98+120,'<I',1),
                (0x98+208,'<I',1),(0x98+216,'<I',1),
                (0x188+36,'<I',0x40000040)):
            data=image();struct.pack_into(fmt,data,at,value)
            with self.subTest(at=at): self.inspect_both(data)


if __name__ == '__main__':
    unittest.main()
