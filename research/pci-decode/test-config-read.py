"""Exercise the production config reader with RAM-only protocol callbacks."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        parser.error('Output must be a new directory')
    out.mkdir(parents=True)
    boot = ROOT / 'internal-boot/boot'
    names = subprocess.check_output(['git', 'ls-files', '--', 'internal-boot', 'deps', 'research/profile'],
                                    cwd=ROOT, text=True).splitlines()
    names += ['internal-boot/boot/test_config_read.c', 'research/pci-decode/test-config-read.py']
    inputs = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sorted(set(names))}
    platform = out / 'platform-config.h'
    platform.write_text('#define GU_INTERNAL_PARTITION_INITIALIZER {0x11111111,0,0,{0}}\n'
                        '#define GU_WINDOWS_PARTITION_INITIALIZER {0x22222222,0,0,{0}}\n', encoding='ascii')
    sources = [boot / 'test_config_read.c', boot / 'console-flow.c',
               ROOT / 'internal-boot/unlock/checks.c', ROOT / 'internal-boot/unlock/sha256.c']
    flags = ['-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
             '-D_CRT_SECURE_NO_WARNINGS', '-DGU_FULL_UNLOCK',
             '-I' + str(ROOT / 'deps/edk2/MdePkg/Include'),
             '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64')]

    def exercise(name, defines, replacement=None, mutant=False, local_header=None):
        folder = out / name
        folder.mkdir()
        roots = [{'type': 'file', 'name': str(boot / 'platform-config.h'),
                  'external-contents': str(platform), 'use-external-name': False}]
        if local_header is not None:
            roots.append({'type': 'file', 'name': str(ROOT / 'internal-boot/unlock/profile-local.h'),
                          'external-contents': str(local_header), 'use-external-name': False})
        if replacement is not None:
            changed = folder / 'full-release.c'
            changed.write_text(replacement, encoding='utf-8')
            roots.append({'type': 'file', 'name': str(boot / 'full-release.c'),
                          'external-contents': str(changed), 'use-external-name': False})
        overlay = folder / 'overlay.json'
        overlay.write_text(json.dumps({'version': 0, 'roots': roots}), encoding='utf-8')
        exe = folder / 'config-read.exe'
        command = [args.clang, *flags, *defines, '-ivfsoverlay', str(overlay),
                   *map(str, sources), '-o', str(exe)]
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=90)
        (folder / 'compile.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise RuntimeError(name + ' must compile: ' + result.stderr[-2000:])
        result = subprocess.run([str(exe)], cwd=ROOT, text=True, capture_output=True, timeout=30)
        (folder / 'run.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        if mutant:
            if result.returncode != 1 or 'ASSERTION FAILED' not in result.stderr:
                raise RuntimeError(name + ' must fail an assertion, not crash')
        elif result.returncode or 'PASS 970 production config-reader scenarios' not in result.stdout:
            raise RuntimeError(name + ': ' + (result.stdout + result.stderr)[-2000:])
        print(name + ': ' + ('compiled mutant detected' if mutant else result.stdout.strip()), flush=True)
        return {'case': name, 'defines': defines, 'exit': result.returncode, 'mutant': mutant}

    headless = ['-DGU_HEADLESS_RESEARCH', '-DGU_SINGLE_RTX_CONSOLE', '-DGU_AUTOMATIC_BOOT']
    cases = [exercise('b650m', []), exercise('b650m-headless', headless)]
    for profile in ['B660M_3070TI', 'B660M_3090TI', 'X870_3090TI', 'B660PLUS_3060', 'H610M_3060']:
        cases.append(exercise(profile.lower(), ['-DGU_PROFILE_' + profile, *headless]))
    spec = importlib.util.spec_from_file_location('config_read_synthetic', ROOT / 'research/profile/test_local_topology.py')
    data = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(data)
    for segment in (0, 1, 0xffff):
        capture = data.synthetic_capture(bus=0x2b).replace('segment=0x0 ', f'segment=0x{segment:x} ')
        capture = capture.replace('probe-target seg=0x0000 ', f'probe-target seg=0x{segment:04x} ')
        admitted = data.analyze(capture)
        header = out / f'synthetic-local-{segment:x}.h'
        header.write_text('/* RAM-only synthetic metadata; not LOCAL evidence. */\n'
            '#define GU_LOCAL_PROFILE_GENERATOR 1\n#define GU_PROFILE_NAME "SYNTHETIC-CONFIG-READ"\n' +
            '#define GU_NVGOP_TEXT_BYTES 0x24426U\n#define GU_NVGOP_TEXT_SHA256 "' +
            hashlib.sha256(bytes(0x24426)).hexdigest() + '"\n' +
            '\n'.join(f'#define {key} {value}' for key, value in admitted['defines']) + '\n', encoding='ascii')
        cases.append(exercise(f'local-segment-{segment:x}', ['-DGU_PROFILE_LOCAL', *headless], local_header=header))
    if args.mutations:
        text = (boot / 'full-release.c').read_text(encoding='utf-8')
        changes = {
            'zero-initial-location': ('UINTN seg=~(UINTN)0,bus=seg,dev=seg,fun=seg;', 'UINTN seg=0,bus=seg,dev=seg,fun=seg;'),
            'same-read-fill': ('pass?0x5a5a5a5aU:0xa5a5a5a5U', '0xa5a5a5a5U'),
            'skip-read-equality': ('if(!Bytes(observed[0],observed[1],sizeof(observed[0])))', 'if(FALSE)'),
            'skip-method-binding': ('#define CONFIG_BOUND (Full.Table==table', '#define CONFIG_BOUND (TRUE || Full.Table==table'),
            'publish-on-refusal': ('if(!cfg || !table || !table->BootServices)return EFI_INVALID_PARAMETER;',
                                   'if(!cfg || !table || !table->BootServices)return EFI_INVALID_PARAMETER; cfg[0]=0;'),
            'skip-final-interface': ('final!=io)return EFI_NOT_READY;', 'FALSE)return EFI_NOT_READY;'),
        }
        for name, (old, new) in changes.items():
            if text.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            cases.append(exercise(name, [], text.replace(old, new), mutant=True))
    if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != sha for name, sha in inputs.items()):
        raise RuntimeError('Source changed during verification')
    (out / 'summary.json').write_text(json.dumps({'passed': True, 'ram_only': True,
        'hardware_access': False, 'source_sha256': inputs, 'cases': cases}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
