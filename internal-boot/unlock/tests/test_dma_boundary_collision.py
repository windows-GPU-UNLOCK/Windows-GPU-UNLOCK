#!/usr/bin/env python3
"""Test exact-boundary fixture allocation and Map callbacks using opaque pointers.

No pointer is dereferenced or reserved. Full port suites separately exercise the
production range check on real host RAM. GCC and optional ASan/UBSan only.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

def callback(source, name):
    """Extract one existing callback, failing if it is renamed or removed."""
    start = source.index('static EFI_STATUS EFIAPI ' + name + '(')
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

HARNESS = r'''
#include "port.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
static struct {
  UINTN allocs, maps;
  int exact_dma, alloc_fail, map_fail, high_map, unaligned_map, short_map;
  UINT64 next_dma;
} fake;
static unsigned calls, releases, live;
static int scenario;
static UINTN bytes_expected;
static VOID *first, *second;
static VOID *scripted_alloc(UINTN bytes, UINTN alignment) {
  assert(bytes==bytes_expected && alignment==4096);
  calls++;
  assert(calls<=2);
  if(calls==1) {
    if(scenario==3)return NULL;
    first=(VOID *)(UINTN)(scenario==0?0x20000000ULL:0xfffff000ULL);
    live|=1;return first;
  }
  /* The first allocation MUST still be live when replacing it. */
  assert(live==1 && first==(VOID *)(UINTN)0xfffff000ULL);
  if(scenario==2)return NULL;
  second=(VOID *)(UINTN)0x20001000ULL;
  assert(second!=first);live|=2;return second;
}
static VOID scripted_free(VOID *p) {
  if(p==first){assert(live&1);live&=~1U;}
  else {assert(p==second && (live&2));live&=~2U;}
  releases++;
}
#define _aligned_malloc scripted_alloc
#define _aligned_free scripted_free
CALLBACKS
int main(int argc,char **argv) {
  assert(argc==3);scenario=atoi(argv[1]);
  bytes_expected=atoi(argv[2]);assert(bytes_expected==4096 || bytes_expected==8192);
  fake.next_dma=0xfffff000ULL;fake.exact_dma=1;
  VOID *cpu=(VOID *)(UINTN)1;
  EFI_STATUS status=allocate(NULL,AllocateAnyPages,EfiBootServicesData,
                            bytes_expected/4096,&cpu,0);
  assert(fake.allocs==1);
  if(scenario==2 || scenario==3) {
    assert(status==EFI_OUT_OF_RESOURCES && !cpu && !live);
    assert(calls==(scenario==2?2U:1U) && releases==(scenario==2?1U:0U));
    assert(!fake.maps && fake.next_dma==0xfffff000ULL);
  } else {
    assert(status==EFI_SUCCESS && cpu);
    EFI_PHYSICAL_ADDRESS dma=0;VOID *mapping=NULL;UINTN bytes=bytes_expected;
    assert(map(NULL,EfiPciIoOperationBusMasterCommonBuffer,cpu,&bytes,&dma,&mapping)==EFI_SUCCESS);
    /* Baseline Map skips to 0x100000000 on collision and fails here. */
    assert(dma==0xfffff000ULL && dma!=(UINT64)(UINTN)cpu && bytes==bytes_expected);
    assert(calls==(scenario==1?2U:1U) && releases==(scenario==1?1U:0U));
    assert(fake.maps==1 && mapping && !(dma&4095));
    assert((bytes-1<=0xffffffffULL-dma)==(bytes==4096));
    scripted_free(cpu);assert(!live && releases==calls);
  }
  puts("PASS: exact DMA fixture allocation, liveness and cleanup");
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
    source = (root / 'internal-boot/unlock/tests/test_port.c').read_text()
    functions = '\n'.join(callback(source, name) for name in ('allocate', 'map'))
    failures = []
    with tempfile.TemporaryDirectory(prefix='gu-dma-boundary-') as temp:
        cfile, exe = Path(temp) / 'boundary.c', Path(temp) / 'boundary'
        cfile.write_text(HARNESS.replace('CALLBACKS', functions))
        flags = ['-std=c11', '-fshort-wchar', '-O1', '-g', '-Wall', '-Wextra', '-Werror']
        if args.sanitize:
            flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-no-pie']
        subprocess.run([args.cc, *flags,
                        '-I' + str(root / 'internal-boot/unlock'),
                        '-I' + str(root / 'deps/edk2/MdePkg/Include'),
                        '-I' + str(root / 'deps/edk2/MdePkg/Include/X64'),
                        str(cfile), '-o', str(exe)], check=True)
        for mode, label in enumerate(('ordinary', 'collision', 'replacement-failure', 'initial-failure')):
            for size in (4096, 8192):
                result = subprocess.run([str(exe), str(mode), str(size)], capture_output=True, text=True)
                name = f'{label} rounded-bytes={size}'
                print(f'{name}: exit={result.returncode}', flush=True)
                if result.returncode:
                    failures.append(name)
                    print(result.stderr.strip(), flush=True)
    if failures:
        raise SystemExit('FAIL: ' + ', '.join(failures))
    print('PASS: all eight exact-boundary fixture cases (opaque pointers only)')


if __name__ == '__main__':
    main()
