"""Compile the actual child display gate against host-only EFI mocks."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--clang', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--capture', type=Path, help='Optional existing child report; read-only config fixture')
    p.add_argument('--mutations', action='store_true')
    p.add_argument('--automatic-ui', action='store_true', help='RAM-only automatic no-U Arm gate')
    args = p.parse_args()
    out = args.output.resolve()
    if out.exists():
        p.error('Output must be a new directory')
    out.mkdir(parents=True)
    core = ['port.c', 'compat.c', 'vendor/unlock_610.c', 'vendor/prep_610.c',
            'vendor/layout_610.c', 'vendor/vbios_610.c', 'vendor/gfw_eval.c']
    source = ROOT / 'research/amd-retained/test_child_display.c'
    files = [source, *(ROOT / 'internal-boot/unlock' / f for f in
             ['app_io.c', 'ownership.c', 'format.c', 'sha256.c', 'checks.c', *core])]
    exe = out / 'child-display.exe'
    flags = ['-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
             '-Wno-unused-function', '-D_CRT_SECURE_NO_WARNINGS', '-D__KERNEL__', '-DGU_UEFI_PORT',
             '-DGU_TARGET_PCI_ID=0x220410deU', '-I' + str(ROOT / 'internal-boot/unlock/compat'),
             '-I' + str(ROOT / 'internal-boot/unlock'),
             '-I' + str(ROOT / 'deps/edk2/MdePkg/Include'), '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64')]
    stages = []
    platform_input = None
    if args.automatic_ui:
        # Compile-only RAM media identity; never generate or replace local configuration.
        (out / 'platform-config.h').write_text(
            '#define GU_INTERNAL_PARTITION_INITIALIZER {0x11111111,0,0,{0}}\n'
            '#define GU_WINDOWS_PARTITION_INITIALIZER {0x22222222,0,0,{0}}\n', encoding='ascii')
        local_platform = ROOT / 'internal-boot/boot/platform-config.h'
        platform = local_platform if local_platform.exists() else out / 'platform-config.h'
        platform_input = {'synthetic': not local_platform.exists(),
                          'sha256': hashlib.sha256(platform.read_bytes()).hexdigest()}
        flags += ['-I' + str(out)]
        flags += ['-DGU_EXPERIMENTAL_3090', '-DGU_INTERNAL_BOOT', '-DGU_ENTRY_LATCHED_SS1_FULL', '-DGU_AUTOMATIC_BOOT']
    for name, cmd in [('compile', [args.clang, *flags, *map(str, files), '-o', str(exe)]), ('run', [str(exe)])]:
        r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=60)
        (out / (name + '.log')).write_text(r.stdout + r.stderr, encoding='utf-8')
        stages.append({'stage': name, 'exit': r.returncode})
        if r.returncode:
            raise RuntimeError(name + ': ' + (r.stdout + r.stderr)[-2000:])
        if name == 'run':
            print(r.stdout.strip())
    for case, defines in [('b650m', []), ('headless', ['-DGU_HEADLESS_RESEARCH']),
                          ('b660m', ['-DGU_PROFILE_B660M_3070TI'])]:
        matrix_exe = out / (case + '-paths.exe')
        for name, cmd in [(case + '-compile', [args.clang, *flags, *defines,
                           str(ROOT / 'research/amd-retained/test_child_paths.c'),
                           str(ROOT / 'internal-boot/unlock/checks.c'), '-o', str(matrix_exe)]),
                          (case + '-run', [str(matrix_exe)])]:
            r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=30)
            (out / (name + '.log')).write_text(r.stdout + r.stderr, encoding='utf-8')
            stages.append({'stage': name, 'exit': r.returncode})
            if r.returncode:
                raise RuntimeError(name + ': ' + (r.stdout + r.stderr)[-2000:])
            if name.endswith('run'):
                print(case + ': ' + r.stdout.strip())
    mutants = []
    if args.mutations:
        app = ROOT / 'internal-boot/unlock/app.c'
        text = app.read_text()
        changes = {
            'allow-late-path-drift': ('AmdDisplayPathPinned && !SameAmdDisplayPath(candidate,AmdDisplayPathPin)', 'FALSE'),
            'pin-failed-first-check': ('if(valid && !AmdDisplayPathPinned)', 'if(!AmdDisplayPathPinned)'),
            'retain-pin-across-entry': ('AmdDisplayPathPinned=FALSE;memset(AmdDisplayPathPin,0,sizeof(AmdDisplayPathPin));', '(void)AmdDisplayPathPin;'),
            'accept-partial-location': ('UINTN s=~(UINTN)0,b=s,d=s,f=s;', 'UINTN s=0,b=s,d=s,f=s;'),
        }
        for name, (old, new) in changes.items():
            if text.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            changed_app = out / (name + '-app.c')
            changed_app.write_text(text.replace(old, new))
            fixture = out / (name + '-fixture.c')
            fixture.write_text(source.read_text().replace(
                '../../internal-boot/unlock/tests/test_3090_preflight.c',
                (ROOT / 'internal-boot/unlock/tests/test_3090_preflight.c').as_posix()).replace(
                '../../internal-boot/unlock/app.c', changed_app.as_posix()))
            mutant_exe = out / (name + '.exe')
            r = subprocess.run([args.clang, *flags, str(fixture), *map(str, files[1:]), '-o', str(mutant_exe)],
                               cwd=ROOT, text=True, capture_output=True, timeout=30)
            (out / (name + '-compile.log')).write_text(r.stdout + r.stderr)
            if r.returncode:
                raise RuntimeError('Mutant must compile: ' + name + '\n' + r.stderr[-2000:])
            r = subprocess.run([str(mutant_exe)], cwd=ROOT, text=True, capture_output=True, timeout=30)
            (out / (name + '-run.log')).write_text(r.stdout + r.stderr)
            if r.returncode != 1 or 'ASSERTION FAILED' not in r.stderr:
                raise RuntimeError('Mutant must fail an assertion: ' + name)
            mutants.append(name)
    capture_sha = None
    if args.capture:
        data = args.capture.read_bytes()
        rows = re.findall(r'^config\[([0-9a-f]+)\]=([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8})',
                          data.decode('utf-8'), re.M)
        if len(rows) != 16 or [int(r[0], 16) for r in rows] != list(range(0, 256, 16)):
            raise RuntimeError('Need one complete ordered config snapshot')
        words = [w for r in rows for w in r[1:]]
        capture = out / 'config-fixture.txt'
        capture.write_text(''.join(f'config_offset=0x{i*4:x}\nvalue=0x{w}\n' for i, w in enumerate(words)))
        checks = out / 'checks.exe'
        for name, cmd in [('checks-compile', [args.clang, *flags, str(ROOT / 'internal-boot/unlock/tests/test_checks.c'),
                          str(ROOT / 'internal-boot/unlock/checks.c'), '-o', str(checks)]),
                          ('checks-run', [str(checks), str(capture)])]:
            r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=30)
            (out / (name + '.log')).write_text(r.stdout + r.stderr, encoding='utf-8')
            stages.append({'stage': name, 'exit': r.returncode})
            if r.returncode:
                raise RuntimeError(name + ': ' + (r.stdout + r.stderr)[-2000:])
            if name.endswith('run'):
                print(r.stdout.strip())
        capture_sha = hashlib.sha256(data).hexdigest()
    inputs = [*files, ROOT / 'internal-boot/unlock/app.c', ROOT / 'internal-boot/unlock/checks.h',
              ROOT / 'internal-boot/unlock/machine-profile.h', Path(__file__).resolve(),
              ROOT / 'research/amd-retained/test_child_paths.c',
              *(ROOT / 'internal-boot/unlock/tests' / f for f in
                ['test_checks.c', 'test_efi_transaction.c', 'test_app.c', 'test_3090_preflight.c'])]
    (out / 'summary.json').write_text(json.dumps({'passed': True, 'ram_only': True, 'stages': stages,
        'automatic_media_config': platform_input,
        'existing_capture_sha256': capture_sha,
        'compiled_mutations_detected': mutants,
        'source_sha256': {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}}, indent=2))


if __name__ == '__main__':
    main()
