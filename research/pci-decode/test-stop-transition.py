"""Build/run pure post-Stop RAM predicates, never EFI or hardware services."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('Output must be a new directory')
    output.mkdir(parents=True)
    includes = ['-I' + str(ROOT / 'deps/edk2/MdePkg/Include'),
                '-I' + str(ROOT / 'deps/edk2/MdePkg/Include/X64'), '-I' + str(HERE)]
    flags = [args.clang, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror',
             '-Wno-unused-parameter', '-D_CRT_SECURE_NO_WARNINGS', *includes]
    stages = []

    def run(name, command, expect_failure=False):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
        (output / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if (result.returncode != 0) != expect_failure:
            raise RuntimeError(name + ': ' + (result.stdout + result.stderr)[-2000:])
        if expect_failure and name.endswith('-run') and (result.returncode != 1 or 'FAIL ' not in result.stderr):
            raise RuntimeError('Mutant must fail an assertion, not crash: ' + name)
        stages.append({'stage': name, 'exit': result.returncode})
        return result.stdout.strip()

    def build(name, source):
        executable = output / (name + '.exe')
        run(name + '-compile', [*flags, str(HERE / 'test_stop_transition.c'),
                               str(source), str(HERE / 'snapshot.c'), '-o', str(executable)])
        return executable

    passed = run('run', [str(build('normal', HERE / 'stop-transition.c'))])
    print(passed)
    run('freestanding', [args.clang, '-target', 'x86_64-pc-win32-coff', '-ffreestanding',
                         '-fshort-wchar', '-mno-red-zone', '-std=c11', '-O2', '-Wall',
                         '-Wextra', '-Werror', '-Wno-unused-parameter', *includes,
                         '-c', str(HERE / 'stop-transition.c'),
                         '-o', str(output / 'stop-transition.obj')])
    mutations = []
    if args.mutations:
        original = (HERE / 'stop-transition.c').read_text(encoding='utf-8')
        changes = {
            'ignore-late-config': ('for(UINTN i=0;i<64;i++)', 'for(UINTN i=0;i<16;i++)'),
            'ignore-parents': ('i<before->ParentCount;i++)\n    if(!SameDevice(&before->Parents[i],&after->Parents[i],0,0))\n      return GU_DS_STOP_REFUSED;',
                              'i<0;i++)\n    if(!SameDevice(&before->Parents[i],&after->Parents[i],0,0))\n      return GU_DS_STOP_REFUSED;'),
            'mask-unknown-cache': ('b->Attributes!=(a->Attributes&~cleared)',
                                   '(b->Attributes&0x700)!=(a->Attributes&~cleared)'),
            'forget-memory-support': ('if(missing && !(before->Gpu.Supported&GU_DS_MEMORY))', 'if(FALSE)'),
            'wrong-result': ('return missing?GU_DS_STOP_MEMORY_OFF:GU_DS_STOP_UNCHANGED;',
                             'return GU_DS_STOP_UNCHANGED;'),
            'accept-uncorrected-baseline': ('before->Gpu.Attributes!=GU_DS_MEMORY', 'FALSE'),
            'allow-memory-on-released-state': ('(after->Gpu.Config[1]&0xffffU)!=0', 'FALSE'),
            'derive-uncorrected-target': ('plan->PlannedGpu.Attributes=GU_DS_MEMORY;', 'plan->PlannedGpu.Attributes=before->Gpu.Attributes;'),
            'ignore-planned-config': ('SameDevice(&plan->PlannedGpu,&derived.PlannedGpu,0,0)', 'TRUE'),
            'accept-corrected-as-uncorrected': ('before->Gpu.Attributes!=(GU_DS_IO|GU_DS_MEMORY)', 'FALSE'),
        }
        for name, (old, new) in changes.items():
            if original.count(old) != 1:
                raise RuntimeError('Mutation anchor changed: ' + name)
            source = output / (name + '.c')
            source.write_text(original.replace(old, new), encoding='utf-8')
            executable = build(name, source)
            run(name + '-run', [str(executable)], expect_failure=True)
            mutations.append(name)
    files = ['stop-transition.h', 'stop-transition.c', 'snapshot.h', 'snapshot.c',
             'test_stop_transition.c', 'test-stop-transition.py']
    summary = {'ram_only': True, 'passed': True, 'result': passed,
               'compiled_mutations_detected': mutations, 'stages': stages,
               'source_sha256': {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest()
                                 for name in files}}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('PASS: ' + str(len(mutations)) + ' compiled guard mutations detected')


if __name__ == '__main__':
    main()
