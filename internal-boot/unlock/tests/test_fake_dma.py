#!/usr/bin/env python3
"""Exercise actual fake Map callbacks, without assets or fixed-address mappings.

Run: python internal-boot/unlock/tests/test_fake_dma.py --cc gcc
Only compiles callback excerpts from the two transaction and port fixtures.
Synthetic CPU pointer values are compared, never dereferenced. This is not an
EFI transaction, firmware execution, hardware qualification or write evidence.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def callback(source, name):
    start = source.index('static EFI_STATUS EFIAPI ' + name + '(')
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


COMMON = r'''
#include "port.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) assert(x)
static EFI_PCI_IO_PROTOCOL pci;
'''
TRANSACTION = r'''
enum {MAP_FAIL=1, MAP_PARTIAL=2};
typedef struct {VOID *cpu; UINTN bytes; UINT64 dma; BOOLEAN mapped,freed;} TEST_BUFFER;
static TEST_BUFFER buffer;
static struct {UINT64 next_dma; UINTN maps,live_maps; int mode;} fake;
static TEST_BUFFER *cpu_buffer(VOID *cpu) {assert(cpu==buffer.cpu);return &buffer;}
'''
PORT = r'''
static struct {
  UINT64 next_dma; UINTN maps;
  int map_fail,high_map,unaligned_map,short_map;
} fake;
'''
MAIN = r'''
int main(int argc,char **argv) {
  (void)argc;
  UINT64 previous_end=0;
  fake.next_dma=0x12000000;
  for(int i=0;i<3;i++) {
    /* Force exact identity on each mapping, without reserving host addresses. */
    UINT64 host=argv[1][0]=='c'?fake.next_dma:0x700000000000ULL;
    VOID *cpu=(VOID *)(UINTN)host,*mapping=NULL;
    UINTN bytes=i==1?65536:8192,requested=bytes;
    EFI_PHYSICAL_ADDRESS dma=0;
    PREPARE
    assert(CALL==EFI_SUCCESS);
    assert(dma!=host && !(dma&4095) && dma>=previous_end);
    assert(bytes==requested && dma<=0xffffffffULL &&
           requested-1<=0xffffffffULL-dma);
    assert(mapping && fake.maps==(UINTN)i+1);
    previous_end=dma+requested;
  }
  puts("PASS: non-identity, aligned, ordered, disjoint 32-bit fake DMA ranges");
  return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--source-root', type=Path,
                        default=Path(__file__).resolve().parents[3])
    parser.add_argument('--sanitize', action='store_true')
    args = parser.parse_args()
    root = args.source_root.resolve()
    failures = []
    with tempfile.TemporaryDirectory(prefix='gu-fake-dma-') as temp:
        for tree in ('unlock', 'internal-boot/unlock'):
            for name in ('test_port.c', 'test_efi_transaction.c'):
                transaction = name == 'test_efi_transaction.c'
                function = 'map_buffer' if transaction else 'map'
                prepare = ('buffer=(TEST_BUFFER){cpu,bytes,0,FALSE,FALSE};'
                           if transaction else '')
                call = function + '(&pci,EfiPciIoOperationBusMasterCommonBuffer,cpu,&bytes,&dma,&mapping)'
                source = COMMON + (TRANSACTION if transaction else PORT)
                source += callback((root / tree / 'tests' / name).read_text(), function)
                source += MAIN.replace('PREPARE', prepare).replace('CALL', call)
                cfile = Path(temp) / 'map.c'
                exe = Path(temp) / 'map-test'
                cfile.write_text(source)
                flags = ['-std=c11', '-fshort-wchar', '-O1', '-g', '-Wall', '-Wextra', '-Werror']
                if args.sanitize:
                    flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-no-pie']
                subprocess.run([args.cc, *flags, '-I' + str(root / tree),
                                '-I' + str(root / 'deps/edk2/MdePkg/Include'),
                                '-I' + str(root / 'deps/edk2/MdePkg/Include/X64'),
                                str(cfile), '-o', str(exe)], check=True)
                for mode in ('ordinary', 'collision'):
                    result = subprocess.run([str(exe), mode], capture_output=True, text=True)
                    label = f'{tree}/{name} {mode}'
                    print(f'{label}: exit={result.returncode}', flush=True)
                    if result.returncode:
                        failures.append(label)
                        print(result.stderr.strip(), flush=True)
    if failures:
        raise SystemExit('FAIL: ' + ', '.join(failures))
    print('PASS: all eight callback cases (RAM-only; no firmware assets)')


if __name__ == '__main__':
    main()
