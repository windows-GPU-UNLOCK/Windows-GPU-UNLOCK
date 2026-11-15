"""Compile the actual status comparator without private firmware fixtures.

The bounded extraction deliberately fails if the trusted source layout changes.
No supplied source, capture, binary or hardware is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clang', default='clang')
    ap.add_argument('--output', required=True)
    args = ap.parse_args()
    repo = Path(__file__).resolve().parents[2]
    source = repo / 'internal-boot/boot/full-release.c'
    text = source.read_text(encoding='utf-8')
    matches = re.findall(r'static BOOLEAN VerifyConfigWord\([^\n]+\) \{\n.*?\n\}', text, re.S)
    if len(matches) != 1 or len(matches[0]) > 2048:
        raise ValueError('Comparator extraction changed; stop for source review')
    function = matches[0]
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=False)
    harness = r'''
#include <stdint.h>
#include <stdio.h>
typedef unsigned BOOLEAN;
typedef uintptr_t UINTN;
typedef uint32_t UINT32;
#define TRUE 1
#define FALSE 0
static struct {UINT32 Config[64];} Full;
FUNCTION
static unsigned count;
static int check(BOOLEAN result, BOOLEAN expected) {
  count++;
  if (!!result != !!expected) return 1;
  return 0;
}
int main(void) {
  Full.Config[30]=0x0012b410;
  for (unsigned w=0;w<64;w++) {
    UINT32 before=0x00092930;
    if(check(VerifyConfigWord(w,before,before,TRUE),TRUE) ||
       check(VerifyConfigWord(w,before,before,FALSE),TRUE)) return 1;
    for(unsigned b=0;b<32;b++) {
      UINT32 after=before^(1U<<b);
      BOOLEAN allowed=w==32 && (b==16 || b==19);
      if(check(VerifyConfigWord(w,before,after,FALSE),allowed) ||
         check(VerifyConfigWord(w,before,after,TRUE),FALSE)) return 1;
    }
  }
  for(unsigned before=0;before<16;before++)
    for(unsigned after=0;after<16;after++) {
      BOOLEAN allowed=!(after & ~before) && !((before^after)&~9U);
      if(check(VerifyConfigWord(32,0x2930|(before<<16),0x2930|(after<<16),FALSE),allowed)) return 1;
    }
  if(check(VerifyConfigWord(32,0x92930,0x2930,FALSE),TRUE) ||
     check(VerifyConfigWord(32,0x92930,0x2930,TRUE),FALSE)) return 1;
  Full.Config[30]^=0x10000;
  if(check(VerifyConfigWord(32,0x92930,0x2930,FALSE),FALSE)) return 1;
  printf("%u\n",count);
  return 0;
}
'''.replace('FUNCTION', function)
    # Compile independent mutations as well: an ineffective harness must fail.
    variants = {'actual': function,
                'cold-waiver': function.replace('checkCold || ', ''),
                'offset-waiver': function.replace('word!=0x80/4 || ', ''),
                'capability-waiver': function.replace(' || Full.Config[0x78/4]!=0x0012b410', ''),
                'new-error-waiver': function.replace('!(observed & clearable & ~expected)', 'TRUE')}
    counts = None
    for name, body in variants.items():
        if name != 'actual' and body == function:
            raise ValueError('Mutation anchor changed')
        c = out / (name + '.c')
        exe = out / (name + '.exe')
        c.write_text(harness.replace(function, body), encoding='ascii')
        subprocess.run([args.clang, '-std=c11', '-O1', '-Wall', '-Wextra',
                        '-Werror', '-Wno-unused-parameter', str(c), '-o', str(exe)],
                       check=True, capture_output=True, timeout=45)
        result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=15)
        if name == 'actual':
            if result.returncode != 0:
                raise ValueError('Actual comparator regression failed')
            counts = int(result.stdout.strip())
        elif result.returncode == 0:
            raise ValueError('Guard mutation survived: ' + name)
    summary = {'Test': 'actual-pci-status-comparator-v1', 'Passed': True,
               'SourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
               'ComparatorSha256': hashlib.sha256(function.encode()).hexdigest(),
               'Assertions': counts, 'GuardMutationsDetected': len(variants)-1,
               'PrivateFirmwareRequired': False, 'HardwareAccess': False,
               'EfiExecuted': False, 'LaptopProfileAdmitted': False, 'WriteEligible': False,
               'Context': 'Pure comparison only; does not establish transaction/FLR/cleanup readiness'}
    (out / 'pci-status.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
