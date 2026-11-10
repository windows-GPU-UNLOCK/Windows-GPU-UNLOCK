"""Compile and adversarially test opt-in MEMORY restoration in host RAM only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--clang', default='clang')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--mutations', action='store_true')
    args = p.parse_args()
    out = args.output.resolve()
    if out.exists():
        p.error('Output must be a new directory')
    out.mkdir(parents=True)
    flags = [args.clang, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror',
             '-Wno-unused-parameter', '-D_CRT_SECURE_NO_WARNINGS', '-DGU_DS_POST_STOP_RESTORE=1',
             '-DGU_DS_POST_STOP_CAPTURE=1',
             '-DGU_DS_HOST_WORKSPACE_TEST', '-I' + str(HERE),
             '-I' + str(ROOT / 'deps/edk2/MdePkg/Include'), '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64')]
    stages = []

    def run(name, command, failure=False):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
        (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if (result.returncode != 0) != failure:
            raise RuntimeError(name + ': ' + (result.stdout + result.stderr)[-2000:])
        if failure and name.endswith('-run') and (result.returncode != 1 or 'FAIL ' not in result.stderr):
            raise RuntimeError('Mutant must fail an assertion, not crash: ' + name)
        stages.append({'stage': name, 'exit': result.returncode})
        return result.stdout.strip()

    def build(name, source):
        exe = out / (name + '.exe')
        run(name + '-compile', [*flags, str(HERE / 'test_efi_restore.c'), str(source),
            *(str(HERE / f) for f in ('decode-sync.c', 'snapshot.c', 'stop-transition.c', 'efi-capture.c')), '-o', str(exe)])
        return exe

    result = run('run', [str(build('normal', HERE / 'efi-adapter.c'))])
    print(result)
    mutations = []
    if args.mutations:
        original = (HERE / 'efi-adapter.c').read_text(encoding='utf-8')
        changes = {
            'enable-io-instead-of-memory': ('s=g->Attributes(g->Pin.Io,EfiPciIoAttributeOperationEnable,GU_DS_MEMORY,NULL);',
                's=g->Attributes(g->Pin.Io,EfiPciIoAttributeOperationEnable,GU_DS_IO,NULL);'),
            'promote-enable-error': ('if(s!=EFI_SUCCESS) {\n      if(cleanup==EFI_SUCCESS)RestoreRead(a,&DisableSnapshot);\n      return RestoreFinish(c,t,GU_DR_ENABLE_FAILED);\n    }', '(void)s;'),
            'ignore-initial-stop-drift': ('if(!GuDecodeSnapshotMatches(&DisableSnapshot,&RestoreInitial,FALSE))return RestoreFinish(c,t,GU_DR_DRIFT);', ''),
            'ignore-final-drift': ('if(!GuDecodeSnapshotMatches(&DisableSnapshot,&a->Expected,FALSE))return RestoreFinish(c,t,GU_DR_DRIFT);\n  return RestoreFinish', 'return RestoreFinish'),
            'accept-fresh-restore-reentry': ('if(c && t && WorkspaceBusy)return GU_DR_REUSED;', 'if(FALSE)return GU_DR_REUSED;'),
            'free-private-restore-report': (' || Overlap(p,n,&RestoreReport,sizeof(RestoreReport))', ''),
            'free-private-stop-snapshot': ('Overlap(p,n,&RestoreInitial,sizeof(RestoreInitial)) || ', ''),
            'ignore-restore-cleanup-failure': ('if(cleanup!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_OWNERSHIP_FAILED);', '(void)cleanup;'),
            'skip-released-plan-validation': ('if(!GuDsReleasePlanMatches(plan,before,after))', 'if(FALSE)'),
            'use-mutable-released-observation': ('GuDecodeSnapshotMatches(&RestoreInitial,&a->ReleasedAfter,FALSE)',
                'GuDecodeSnapshotMatches(&RestoreInitial,a->InputReleasedAfter,FALSE)'),
            'omit-initial-released-pin': ('if(a->ReleasedOrigin && !GuDecodeSnapshotMatches(&RestoreInitial,&a->ReleasedAfter,FALSE))', 'if(FALSE)'),
            'omit-origin-report': ('RestoreReport.ReleasedOrigin=a->ReleasedOrigin;', 'RestoreReport.ReleasedOrigin=FALSE;'),
            'accept-noncanonical-origin': ('if(c->ReleasedOrigin!=FALSE && c->ReleasedOrigin!=TRUE)', 'if(FALSE)'),
            'downgrade-origin-with-history': ('if(!c->ReleasedOrigin && (c->InputReleasedAfter',
                'if(FALSE && !c->ReleasedOrigin && (c->InputReleasedAfter'),
            'free-original-released-observation': (
                '(c->ReleasedOrigin && (Overlap(p,n,c->InputReleasedAfter,sizeof(*c->InputReleasedAfter)) ||\n       Overlap(p,n,c->InputReleasePlan,sizeof(*c->InputReleasePlan)))) ||',
                '(c->ReleasedOrigin && Overlap(p,n,c->InputReleasePlan,sizeof(*c->InputReleasePlan))) ||'),
        }
        for name, (old, new) in changes.items():
            if original.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            source = out / (name + '.c')
            broken = original.replace(old, new)
            if name == 'free-private-stop-snapshot':
                # This snapshot is also covered by ActiveOutput; remove both
                # overlapping defenses to create an actually unsafe mutant.
                anchor = 'a->ActiveOutput=&RestoreInitial;'
                if broken.count(anchor) != 1:
                    raise RuntimeError('Active output mutation anchor changed')
                broken = broken.replace(anchor, 'a->ActiveOutput=NULL;')
            source.write_text(broken, encoding='utf-8')
            run(name + '-run', [str(build(name, source))], failure=True)
            mutations.append(name)
    for value in ('0', '2'):
        run('invalid-define-' + value, [*(f for f in flags if f != '-DGU_DS_POST_STOP_RESTORE=1'),
            '-DGU_DS_POST_STOP_RESTORE=' + value, '-fsyntax-only', str(HERE / 'efi-adapter.c')], failure=True)
        if 'GU_DS_POST_STOP_RESTORE must be exactly 1 when enabled' not in (out / ('invalid-define-' + value + '.log')).read_text():
            raise RuntimeError('Invalid feature define failed for unrelated reason')
    files = ['test_efi_restore.c', 'test_efi_adapter.c', 'efi-adapter.c', 'efi-adapter.h',
             'decode-sync.c', 'decode-sync.h', 'snapshot.c', 'snapshot.h', 'stop-transition.c',
             'stop-transition.h', 'efi-binding.h', 'efi-path.h', 'efi-capture.c', 'efi-capture.h', 'test-efi-restore.py']
    summary = {'ram_only': True, 'passed': True, 'result': result,
        'compiled_mutations_detected': mutations, 'stages': stages,
        'source_sha256': {f: hashlib.sha256((HERE / f).read_bytes()).hexdigest() for f in files}}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('PASS ' + str(len(mutations)) + ' compiled mutants and two feature-define rejection guards')


if __name__ == '__main__':
    main()
