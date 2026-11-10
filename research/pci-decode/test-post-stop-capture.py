"""Validate opt-in post-Stop capture using RAM-backed EFI services only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        parser.error('Output must be a new directory')
    out.mkdir(parents=True)
    files = ['efi-capture.c', 'efi-capture.h', 'efi-path.h', 'efi-binding.h', 'snapshot.c',
             'snapshot.h', 'stop-transition.c', 'stop-transition.h', 'test_post_stop_capture.c',
             'test_efi_capture.c', 'test_efi_adapter.c', 'test-post-stop-capture.py',
             'efi-adapter.c', 'efi-adapter.h', 'decode-sync.c', 'decode-sync.h', 'test_iomem_capture.c']
    before = {f: hashlib.sha256((HERE / f).read_bytes()).hexdigest() for f in files}
    flags = [args.clang, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror',
             '-Wno-unused-parameter', '-D_CRT_SECURE_NO_WARNINGS', '-DGU_DS_POST_STOP_CAPTURE=1',
             '-I' + str(HERE), '-I' + str(ROOT / 'deps/edk2/MdePkg/Include'),
             '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64')]
    stages = []

    def run(name, command, failure=False):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
        (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if (result.returncode != 0) != failure:
            raise RuntimeError(name + ': ' + (result.stdout + result.stderr)[-2500:])
        if failure and name.endswith('-run') and (result.returncode != 1 or 'FAIL ' not in result.stderr):
            raise RuntimeError(name + ': require an explicit failed assertion, not a process crash')
        stages.append({'stage': name, 'exit': result.returncode})
        return result.stdout.strip()

    def build(name, source):
        exe = out / (name + '.exe')
        sources = ['test_iomem_capture.c', 'stop-transition.c', 'efi-adapter.c',
                   'decode-sync.c', 'snapshot.c']
        run(name + '-compile', [*flags, *(str(HERE / f) for f in sources), str(source), '-o', str(exe)])
        return exe

    result = run('run', [str(build('normal', HERE / 'efi-capture.c'))])
    print(result)
    mutations = []
    if args.mutations:
        text = (HERE / 'efi-capture.c').read_text(encoding='utf-8')
        changes = {
            'skip-phase-check': ('if(GuDsStopTransition(&ActiveBefore,v)==GU_DS_STOP_REFUSED)', 'if(FALSE)'),
            'use-mutable-baseline': ('GuDsStopTransition(&ActiveBefore,v)', 'GuDsStopTransition(before,v)'),
            'omit-second-scan-equality': ('!GuDecodeSnapshotMatches(&snapshots[1],&snapshots[0],FALSE)', 'FALSE'),
            'ordinary-inherits-post-policy': ('if(!GuDecodeSnapshotValid(v))goto done;',
                'if(v->Gpu.Config[1]&4)goto done;'),
            'accept-fresh-reentry': ('c->Used!=FALSE || ActiveBusy!=FALSE', 'c->Used!=FALSE'),
            'skip-baseline-overlap': ('if(before && (Overlap(before,sizeof(*before),c,sizeof(*c)) ||',
                'if(FALSE && before && (Overlap(before,sizeof(*before),c,sizeof(*c)) ||'),
            'skip-released-mismatch-validation': ('if(!GuDsPlanReleasedMismatch(&ActiveBefore,v,&plan))goto done;', '(void)plan;'),
            'use-mutable-release-baseline': ('GuDsPlanReleasedMismatch(&ActiveBefore,v,&plan)', 'GuDsPlanReleasedMismatch(before,v,&plan)'),
            'skip-iomem-transition': ('if(GuDsIoMemStopTransition(&ActiveBefore,v)==GU_DS_STOP_REFUSED)', 'if(FALSE)'),
            'use-mutable-iomem-origin': ('GuDsIoMemStopTransition(&ActiveBefore,v)', 'GuDsIoMemStopTransition(before,v)'),
            'skip-release-origin-policy': ('if(!GuDsReleaseSnapshotValid(v))goto done;', '(void)0;'),
        }
        for name, (old, new) in changes.items():
            if text.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            source = out / (name + '.c')
            source.write_text(text.replace(old, new), encoding='utf-8')
            run(name + '-run', [str(build(name, source))], failure=True)
            mutations.append(name)
    for value in ('0', '2'):
        run('invalid-define-' + value, [*(f for f in flags if f != '-DGU_DS_POST_STOP_CAPTURE=1'),
             '-DGU_DS_POST_STOP_CAPTURE=' + value, '-c', str(HERE / 'efi-capture.c'),
             '-o', str(out / ('invalid-' + value + '.obj'))], failure=True)
        if 'GU_DS_POST_STOP_CAPTURE must be exactly 1 when enabled' not in (out / ('invalid-define-' + value + '.log')).read_text(encoding='utf-8'):
            raise RuntimeError('Invalid define failed for an unrelated reason')
    if any(hashlib.sha256((HERE / f).read_bytes()).hexdigest() != sha for f, sha in before.items()):
        raise RuntimeError('Source changed during collector test')
    summary = {'ram_only': True, 'passed': True, 'result': result,
               'compiled_mutations_detected': mutations, 'stages': stages,
               'source_sha256': before}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('PASS ' + str(len(mutations)) + ' compiled mutations and two define rejection guards')


if __name__ == '__main__':
    main()
