"""Compile actual release phases with typed parent collection; RAM-only synthetic inputs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mismatch', action='store_true')
    parser.add_argument('--mutations', action='store_true')
    parser.add_argument('--edid-driver', action='store_true', help='Replay the actual sequential EDID release stage')
    parser.add_argument('--children', type=int, choices=(1, 2, 3, 4), default=1)
    parser.add_argument('--aggregate', action='store_true', help='Use the separate aggregate GOP frontend')
    parser.add_argument('--iomem', action='store_true', help='Model a coherent command3/cache300 release origin')
    parser.add_argument('--amd-retained', action='store_true', help='Use the fixed B650M retained AMD frontend')
    args = parser.parse_args()
    if args.aggregate and not args.edid_driver:
        parser.error('The aggregate research frontend requires --edid-driver')
    if args.amd_retained and (args.aggregate or not args.edid_driver or args.children > 2):
        parser.error('--amd-retained requires --edid-driver, 1/2 children and no --aggregate')
    if args.iomem and args.mismatch:
        parser.error('--iomem requires a separate run without --mismatch')
    if args.edid_driver and args.children > 2:
        parser.error('The existing EDID-driver policy allows at most two display children')
    if args.mutations and not (args.mismatch or args.iomem):
        parser.error('--mutations requires --mismatch or --iomem')
    out = args.output.resolve()
    if out.exists():
        parser.error('Output must be new')
    out.mkdir(parents=True)
    paths = subprocess.check_output(['git', 'ls-files', '--', 'internal-boot', 'deps', 'research/profile', 'research/pci-decode', 'research/amd-retained'],
                                   cwd=ROOT, text=True).splitlines()
    paths += ['internal-boot/boot/release-parent-audit.h', 'internal-boot/boot/release-ownership-audit.h', 'internal-boot/boot/test_release_parent_audit.c',
              'research/pci-decode/test-release-parent-audit.py', 'internal-boot/boot/test_release_aggregate_audit.c',
              'research/pci-decode/test_iomem_capture.c', 'research/amd-retained/synthetic.py',
              'internal-boot/boot/test_release_amd_audit.c']
    before = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(set(paths))}
    data = load('release_audit_data', ROOT / 'research/profile/test_local_topology.py')
    images = load('release_audit_images', ROOT / 'research/profile/test_compatibility.py')
    command = 3 if args.iomem else 2
    text = data.synthetic_capture(bus=0x2b, children=args.children, command=command, no_edid=not args.edid_driver, aggregate=args.aggregate)
    configuration = data.configuration(command)
    if args.amd_retained:
        retained = load('release_audit_amd', ROOT / 'research/amd-retained/synthetic.py')
        text, configuration = retained.capture(data, children=args.children, command=command)
    admitted = None if args.amd_retained else data.analyze(text)
    header = out / 'profile-local.h'
    header.write_text('/* Synthetic RAM model, not LOCAL qualification. */\n'
        '#define GU_LOCAL_PROFILE_GENERATOR 1\n#define GU_PROFILE_NAME "SYNTHETIC-PARENT-AUDIT"\n'
        '#define GU_NVGOP_TEXT_BYTES 0x24426U\n#define GU_NVGOP_TEXT_SHA256 "' +
        hashlib.sha256(bytes(0x24426)).hexdigest() + '"\n' +
        ('#define GU_EDID_TEXT_BYTES 0x700U\n#define GU_EDID_TEXT_SHA256 "' +
         hashlib.sha256(bytes(0x700)).hexdigest() + '"\n' if args.edid_driver else '') +
        '\n'.join(f'#define {key} {value}' for key, value in (admitted['defines'] if admitted else [])) + '\n', encoding='ascii')
    capture = out / 'capture.txt'
    capture.write_text(text, encoding='ascii')
    nv = out / 'nvgop.bin'
    nv.write_bytes(images.driver_image(0x2b6e0, 0x280, 0x23d6a) if args.amd_retained else images.driver_image(0x2be40, 0x280, 0x24426))
    edid = out / 'edid.bin'
    if args.edid_driver:
        edid.write_bytes(images.driver_image(0x9000, 0x1000, 0x38f8 if args.amd_retained else 0x700))
    prom = out / 'prom.bin'
    prom.write_bytes(bytes(1048576))
    config = out / 'config.bin'
    config.write_bytes(struct.pack('<64I', *configuration))
    platform = out / 'platform-config.h'
    platform.write_text('#define GU_INTERNAL_PARTITION_INITIALIZER {0}\n#define GU_WINDOWS_PARTITION_INITIALIZER {0}\n', encoding='ascii')
    fixture = out / 'replay-fixture.h'

    def run(name, command):
        r = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
        (out / (name + '.log')).write_text(r.stdout + r.stderr, encoding='utf-8')
        if r.returncode:
            raise RuntimeError(name + ': ' + (r.stdout + r.stderr)[-2500:])
        return r.stdout.strip()

    run('fixture', [sys.executable, '-I', str(ROOT / 'internal-boot/boot/make-console-fixture.py'),
        str(capture), *(['--amd-retained-multi'] if args.amd_retained else ['--single-rtx', '--no-igpu']),
        *([] if args.edid_driver else ['--no-edid-driver']),
        *(['--aggregate'] if args.aggregate else []), '--no-edid-child', '--output=' + str(fixture)])
    boot = ROOT / 'internal-boot/boot'
    overlay = out / 'overlay.json'
    overlay.write_text(json.dumps({'version': 0, 'roots': [
        {'type': 'file', 'name': str(path), 'external-contents': str(source), 'use-external-name': False}
        for path, source in [(boot / 'platform-config.h', platform),
            (ROOT / 'internal-boot/unlock/profile-local.h', header), (boot / 'build/r2/replay-fixture.h', fixture),
            (boot / 'build/aggregate/replay-fixture.h', fixture), (boot / 'build/console/replay-fixture.h', fixture)]]}), encoding='utf-8')
    flags = ['-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
        '-D_CRT_SECURE_NO_WARNINGS', '-DGU_PROFILE_LOCAL', '-DGU_HEADLESS_RESEARCH',
        '-DGU_SINGLE_RTX_CONSOLE', '-DGU_FULL_UNLOCK', '-DGU_AUTOMATIC_BOOT',
        '-DGU_RELEASE_PARENT_AUDIT=1', '-DGU_DS_POST_STOP_CAPTURE=1', '-ivfsoverlay', str(overlay),
        '-I' + str(ROOT / 'deps/edk2/MdePkg/Include'), '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64')]
    if args.aggregate:
        flags.append('-DGU_AGGREGATE_CAPTURE_FIXTURE')
    if args.iomem:
        flags.append('-DGU_RELEASE_IOMEM_MODEL')
    if args.amd_retained:
        flags = [f for f in flags if f not in ('-DGU_PROFILE_LOCAL', '-DGU_HEADLESS_RESEARCH', '-DGU_SINGLE_RTX_CONSOLE')]
        flags += ['-DGU_PROFILE_B650M_3090FE', '-DGU_AMD_RETAINED_MULTI_DISPLAY']
    sources = [boot / ('test_release_amd_audit.c' if args.amd_retained else 'test_release_aggregate_audit.c' if args.aggregate else 'test_release_parent_audit.c'), boot / 'console-flow.c',
        *(ROOT / 'internal-boot/unlock' / p for p in ['checks.c', 'sha256.c']),
        *(ROOT / 'research/pci-decode' / p for p in ['efi-capture.c', 'snapshot.c', 'stop-transition.c'])]
    if args.mismatch:
        flags.append('-DGU_RELEASE_MISMATCH_RESEARCH=1')
    exe = out / 'audit.exe'
    run('compile', [args.clang, *flags, *map(str, sources), '-o', str(exe)])
    image_arguments = ([str(edid)] if args.edid_driver else []) + [str(nv), str(prom), str(config)]
    result = run('run', [str(exe), *image_arguments])
    print(result)
    legacy_retained_result = None
    if args.amd_retained and args.children == 2:
        legacy_flags = [f for f in flags if f not in ('-DGU_RELEASE_PARENT_AUDIT=1',
            '-DGU_DS_POST_STOP_CAPTURE=1', '-DGU_RELEASE_IOMEM_MODEL', '-DGU_RELEASE_MISMATCH_RESEARCH=1')]
        legacy_exe = out / 'legacy-retained.exe'
        run('legacy-retained-compile', [args.clang, *legacy_flags, str(boot / 'test_amd_retained.c'),
            str(boot / 'console-flow.c'), str(ROOT / 'internal-boot/unlock/checks.c'),
            str(ROOT / 'internal-boot/unlock/sha256.c'), '-o', str(legacy_exe)])
        legacy_retained_result = run('legacy-retained-run', [str(legacy_exe), str(config)])
        print(legacy_retained_result)
    rejected_images = []
    for label, path, code_offset in [('nvidia', nv, 0x280), *([('edid', edid, 0x1000)] if args.edid_driver else [])]:
        original = path.read_bytes()
        changed = bytearray(original)
        changed[code_offset] ^= 1
        for fault, content in [('truncated', original[:-1]), ('extended', original + b'\0'), ('changed-code', changed)]:
            bad_image = out / (label + '-' + fault + '.bin')
            bad_image.write_bytes(content)
            bad_arguments = [str(bad_image) if value == str(path) else value for value in image_arguments]
            bad = subprocess.run([str(exe), *bad_arguments], cwd=ROOT, text=True, capture_output=True, timeout=30)
            (out / (label + '-' + fault + '.log')).write_text(bad.stdout + bad.stderr, encoding='utf-8')
            if fault in ('truncated', 'extended'):
                expected = ('FAIL aggregate full: input image size mismatch' if args.aggregate else
                    'FAIL exact synthetic EDID image' if label == 'edid' else 'FAIL exact loaded synthetic NVIDIA driver')
            elif label == 'edid':
                expected = ('aggregate event=ami-runtime-code-profile status=800000000000001b' if args.aggregate else
                    "FAIL EDID image matches this model's code pin")
            else:
                expected = ('aggregate' if args.aggregate else 'full') + ' event=nvidia-code-profile status=800000000000001b'
            if bad.returncode != 1 or 'FAIL ' not in bad.stderr or expected not in bad.stderr:
                raise RuntimeError('Invalid image must fail at its length/code-pin check: ' + label + '-' + fault)
            rejected_images.append({'image': label, 'fault': fault, 'exit': bad.returncode, 'expected_diagnostic': expected})
    guards = []
    guard_cases = [
        ('freestanding', [], ['-ffreestanding'], 'hosted research only'),
        ('audit-zero', ['-DGU_RELEASE_PARENT_AUDIT=1'], ['-DGU_RELEASE_PARENT_AUDIT=0'], 'hosted research only'),
        ('missing-capture', ['-DGU_DS_POST_STOP_CAPTURE=1'], [], 'requires the opt-in post-Stop collector'),
        ('standalone-mismatch', ['-DGU_RELEASE_PARENT_AUDIT=1'], ['-DGU_RELEASE_MISMATCH_RESEARCH=1'], 'requires the host-only parent audit')]
    if args.amd_retained:
        guard_cases += [
            ('retained-headless', [], ['-DGU_HEADLESS_RESEARCH'], 'AMD-retained multi-display requires the original B650M'),
            ('retained-other-profile', ['-DGU_PROFILE_B650M_3090FE'], ['-DGU_PROFILE_B660M_3090TI'], 'AMD-retained multi-display requires the original B650M')]
    for name, omit, add, diagnostic in guard_cases:
        guard_flags = [f for f in flags if f not in omit and f != '-DGU_RELEASE_MISMATCH_RESEARCH=1']
        guard = subprocess.run([args.clang, *guard_flags, *add, '-fsyntax-only', str(boot / 'full-release.c')],
                               cwd=ROOT, text=True, capture_output=True, timeout=30)
        (out / (name + '.log')).write_text(guard.stdout + guard.stderr, encoding='utf-8')
        if not guard.returncode or diagnostic not in guard.stderr:
            raise RuntimeError('Expected feature refusal: ' + name)
        guards.append(name)
    mutants = []
    if args.mutations:
        flow = boot / 'full-release.c'
        history = boot / 'release-parent-audit.h'
        ownership = boot / 'release-ownership-audit.h'
        changes = {
            'acquire-after-failed-baseline': (ownership, '!a->OwnershipStarted || !a->OwnerBaselineReady || a->OpenInvoked',
                '!a->OwnershipStarted || a->OpenInvoked'),
            'free-borrowed-parent-handle': (ownership, 'AuditRangeOverlap(p,bytes,a->Devices[i].Pin.Handle,1)', 'FALSE'),
            'free-borrowed-prepared-graph': (ownership,
                '(PreparedGraph && AuditRangeOverlap(p,bytes,PreparedGraph,sizeof(*PreparedGraph)))', 'FALSE'),
            'accept-open-warning': (ownership, 'if(a->OpenStatus!=EFI_SUCCESS)return a->OpenStatus;',
                'if(EFI_ERROR(a->OpenStatus))return a->OpenStatus;'),
            'close-ambiguous-self': (ownership, '*present=own==1 && precise;', '*present=own>=1; (void)precise;'),
            'promote-close-error': (ownership, 'if(a->CloseInvoked && a->CloseStatus!=EFI_SUCCESS)return a->CloseStatus;',
                'if(FALSE)return a->CloseStatus;'),
            'free-owner-proof-before-enable': (ownership,
                'if(s==EFI_SUCCESS && needed)s=a->Devices[0].Attributes(a->ClaimIo,EfiPciIoAttributeOperationEnable,needed,NULL);\n  EFI_STATUS freed=AuditOwnerFree(held);',
                'EFI_STATUS freed=AuditOwnerFree(held);\n  if(s==EFI_SUCCESS && needed)s=a->Devices[0].Attributes(a->ClaimIo,EfiPciIoAttributeOperationEnable,needed,NULL);'),
            'skip-final-parent-comparison': (flow,
                'if(!FinalAuditDevice(&current->Snapshot.Parents[i],&before->Parents[i],\n                        before->Parents[i].Attributes,FALSE,checkCold))',
                'if(FALSE)'),
            'allow-parent-status-clear': (flow,
                'else if(observed->Config[i]!=before->Config[i])return FALSE;',
                'else if(!VerifyConfigWord(i,before->Config[i],observed->Config[i],checkCold))return FALSE;'),
            'skip-recursive-verify-guard': (flow,
                'if(ReleaseAudit.Verifying)return EFI_ALREADY_STARTED;',
                'if(FALSE)return EFI_ALREADY_STARTED;'),
            'overwrite-observed-attributes': (flow, 'Full.TargetAttributes=targetAttributes;',
                'Full.Attributes=targetAttributes&~GU_DS_IO;Full.TargetAttributes=targetAttributes;'),
            'skip-effect-binding': (history, 'a->Boot->OpenProtocol!=a->Open', 'FALSE'),
            'skip-active-release-guard': (flow, 'ReleaseAudit.Active || ReleaseAudit.ReleaseUsed', 'ReleaseAudit.ReleaseUsed'),
            'skip-pre-nv-audit': (flow, 'if(s==EFI_SUCCESS)s=ReleaseAuditObserve(FALSE);', '(void)0;'),
            'skip-final-claim-graph': (flow,
                'if(s==EFI_SUCCESS && !FullExpected(&claimGraph,4))s=EFI_NOT_READY;\n#ifdef GU_RELEASE_PARENT_AUDIT\n  if(s==EFI_SUCCESS && !ReleaseAuditBound())s=EFI_NOT_READY;\n  if(s==EFI_SUCCESS)s=AuditOwnershipEnable(needed);',
                'if(FALSE)s=EFI_NOT_READY;\n#ifdef GU_RELEASE_PARENT_AUDIT\n  if(s==EFI_SUCCESS && !ReleaseAuditBound())s=EFI_NOT_READY;\n  if(s==EFI_SUCCESS)s=AuditOwnershipEnable(needed);'),
        }
        if args.iomem:
            changes.update({
                'misclassify-consistent-iomem': (history,
                    'a->IoMem=(before->Snapshot.Gpu.Config[1]&0xffffU)==3U;', 'a->IoMem=FALSE;'),
                'drop-original-io-target': (history,
                    'if(!a->Mismatch){*target=observed;return EFI_SUCCESS;}',
                    'if(!a->Mismatch){*target=observed&~GU_DS_IO;return EFI_SUCCESS;}'),
            })
            if args.aggregate:
                changes['skip-frozen-iomem-post-state'] = (history,
                    'if(!GuDecodeSnapshotMatches(&current->Snapshot,&a->Captures[a->ActualAfterIndex].Snapshot,FALSE))',
                    'if(FALSE)')
        roots = json.loads(overlay.read_text(encoding='utf-8'))['roots']
        for name, (source, old, new) in changes.items():
            text_source = source.read_text(encoding='utf-8')
            if text_source.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            folder = out / name
            folder.mkdir()
            replacement = folder / source.name
            replacement.write_text(text_source.replace(old, new), encoding='utf-8')
            mutant_overlay = folder / 'overlay.json'
            mutant_overlay.write_text(json.dumps({'version': 0, 'roots': roots + [
                {'type': 'file', 'name': str(source), 'external-contents': str(replacement), 'use-external-name': False}]}), encoding='utf-8')
            mutant_exe = folder / 'mutant.exe'
            mutant_flags = [str(mutant_overlay) if f == str(overlay) else f for f in flags]
            run(name + '-compile', [args.clang, *mutant_flags, *map(str, sources), '-o', str(mutant_exe)])
            bad = subprocess.run([str(mutant_exe), *image_arguments], cwd=ROOT,
                                 text=True, capture_output=True, timeout=30)
            (folder / 'run.log').write_text(bad.stdout + bad.stderr, encoding='utf-8')
            if bad.returncode != 1 or 'FAIL ' not in bad.stderr:
                raise RuntimeError('Mutant must fail an assertion: ' + name)
            mutants.append(name)
            print(name + ': compiled mutant detected', flush=True)
    if any(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != sha for p, sha in before.items()):
        raise RuntimeError('Source changed during test')
    (out / 'summary.json').write_text(json.dumps({'passed': True, 'ram_only': True,
        'efi_executed': False, 'mismatch_admission_enabled': args.mismatch, 'host_only': True,
        'edid_driver': args.edid_driver, 'display_children': args.children, 'aggregate': args.aggregate, 'iomem': args.iomem,
        'amd_retained': args.amd_retained, 'result': result, 'legacy_retained_result': legacy_retained_result,
        'rejected_images': rejected_images,
        'synthetic_input_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
            [capture, header, nv, prom, config, platform, fixture, *([edid] if args.edid_driver else [])]},
        'compile_refusals': guards, 'compiled_mutations_detected': mutants, 'source_sha256': before}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
