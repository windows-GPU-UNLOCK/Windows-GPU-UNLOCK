"""Capture-free host replay of production release with and without an EDID driver.

Synthetic buffers are only hashed/read as data; no vendor code or GPU is used.
Profile/fixture headers are virtual compiler inputs, never installed locally.
"""
import argparse
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BOOT = ROOT / 'internal-boot/boot'
spec = importlib.util.spec_from_file_location('release_topology_data', Path(__file__).with_name('test_local_topology.py'))
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--card', type=lambda value: int(value, 0),
                        help='Select one existing matrix card; never adds admission')
    parser.add_argument('--children', type=int, choices=(1, 2, 3, 4),
                        help='Select an existing child-count dimension')
    parser.add_argument('--mutations', action='store_true',
                        help='Verify child-count refusal and detect removed NVIDIA-profile/child-count guards')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        parser.error('Output must be a new directory')
    out.mkdir(parents=True)
    (out / 'platform-config.h').write_text('#define GU_INTERNAL_PARTITION_INITIALIZER {0}\n#define GU_WINDOWS_PARTITION_INITIALIZER {0}\n')
    def run(name, command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (out / (name + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(name + ': ' + (result.stdout + result.stderr)[-2500:])
        return result.stdout.strip()
    flags = [args.clang, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-fshort-wchar',
             '-D_CRT_SECURE_NO_WARNINGS', '-DGU_PROFILE_LOCAL', '-DGU_HEADLESS_RESEARCH',
             '-DGU_SINGLE_RTX_CONSOLE', '-DGU_FULL_UNLOCK', '-DGU_AUTOMATIC_BOOT',
             '-I', str(out), '-I', str(ROOT / 'deps/edk2/MdePkg/Include'), '-I', str(ROOT / 'deps/edk2/MdePkg/Include/X64')]
    sources = [str(BOOT / 'test_headless_full.c'), str(BOOT / 'console-flow.c'),
               str(ROOT / 'internal-boot/unlock/checks.c'), str(ROOT / 'internal-boot/unlock/sha256.c')]
    summaries, child_checks, image_refusals, mutations, count_refusals = [], [], [], [], []
    envelope=json.loads((ROOT / 'research/profile/proven.json').read_text())
    cards=((0x220410de,0xb72000a1,0x6000),(0x220410de,0xb72000a1,0x5ff4),
           (0x248710de,0xb74000a1,0x3000),(0x250410de,0xb76000a1,0x3000),
           (0x220310de,0xb72000a1,0x5ff4),(0x248410de,0xb74000a1,0x2000),
           (0x24c910de,0xb74000a1,0x2000))
    if args.card is not None:
        cards=tuple(card for card in cards if card[0]==args.card)
        if not cards:
            parser.error('Card is not in the existing synthetic matrix')
    child_counts=(args.children,) if args.children is not None else (1, 2, 3, 4)
    for bus, children, command, (board,chip,memory), no_edid in itertools.product((1, 0x2b), child_counts, (2, 3), cards, (False,True)):
        name = f'id{board:x}-bus{bus:x}-children{children}-cmd{command}-memory{memory:x}-noedid{int(no_edid)}'
        case = out / name
        case.mkdir()
        capture = case / 'DIAG.TXT'
        capture.write_text(data.synthetic_capture(bus=bus, children=children, command=command, memory=memory,
                                                 child_adr=0x10 if bus == 1 else 0xa0, board=board,chip=chip,no_edid=no_edid), encoding='ascii')
        admitted = data.analyze(capture.read_text(), envelope)
        nv_size,nv_text=(0x26ae0,0x20d33) if board in (0x248710de,0x250410de,0x220310de) else (0x2be40,0x24426)
        if board==0x24c910de:nv_size,nv_text=0x26e00,0x2106f
        defines = admitted['defines'] + [
            ('GU_NVGOP_TEXT_BYTES', f'0x{nv_text:x}U'),
            ('GU_NVGOP_TEXT_SHA256', '"' + hashlib.sha256(bytes(nv_text)).hexdigest() + '"')]
        if not no_edid:
            defines += [('GU_EDID_TEXT_BYTES','0x700U'),
                        ('GU_EDID_TEXT_SHA256','"'+hashlib.sha256(bytes(0x700)).hexdigest()+'"')]
        header = case / 'profile-local.h'
        header.write_text('/* Synthetic host-only inputs; not hardware evidence. */\n'
                          '#define GU_LOCAL_PROFILE_GENERATOR 1\n#define GU_PROFILE_NAME "LOCAL-SYNTHETIC-REPLAY"\n' +
                          '\n'.join(f'#define {key} {value}' for key, value in defines) + '\n')
        fixture = case / 'replay-fixture.h'
        run(name + '-fixture', [sys.executable, '-I', str(BOOT / 'make-console-fixture.py'), str(capture),
                              '--single-rtx', '--no-igpu', *(['--no-edid-driver'] if no_edid else []), '--no-edid-child',
                              f'--rtx-id={board:08x}', '--rtx-fb=0x000000fcc0000000', '--output=' + str(fixture)])
        config = data.configuration(command, board)
        import struct
        config_path = case / 'config.bin'
        config_path.write_bytes(struct.pack('<64I', *config))
        prom = case / 'prom.bin'; prom.write_bytes(bytes(1048576))
        nv = case / 'nvgop.bin'; nv.write_bytes(bytes(nv_size))
        edid=case/'edid.bin';edid.write_bytes(bytes(0x9000))
        overlay = case / 'overlay.json'
        overlay.write_text(json.dumps({'version': 0, 'roots': [
            {'type': 'file', 'name': str(ROOT / 'internal-boot/unlock/profile-local.h'), 'external-contents': str(header), 'use-external-name': False},
            {'type': 'file', 'name': str(BOOT / 'build/r2/replay-fixture.h'), 'external-contents': str(fixture), 'use-external-name': False}]}))
        exe = case / ('release.exe' if sys.platform == 'win32' else 'release')
        run(name + '-compile', flags + ['-ivfsoverlay', str(overlay), *sources, '-o', str(exe)])
        images=[str(nv)] if no_edid else [str(edid),str(nv)]
        summary = run(name, [str(exe), *images, str(prom), str(config_path)])
        summaries.append({'case': name, 'result': summary})
        print(name + ': ' + summary, flush=True)
        if args.mutations and not no_edid and not mutations:
            source=(BOOT/'full-release.c').read_text()
            before='if(s==EFI_SUCCESS)s=Profile(stage==3?Full.EdidAgent:Full.NvAgent,stage==3);'
            if source.count(before)!=1:raise RuntimeError('Profile mutation no longer matches source')
            broken=case/'full-release-skipped-profile.c'
            broken.write_text(source.replace(before,before.replace('s==EFI_SUCCESS','s==EFI_SUCCESS && stage!=4')))
            mapping=json.loads(overlay.read_text())
            mapping['roots'].append({'type':'file','name':str(BOOT/'full-release.c'),
                                    'external-contents':str(broken),'use-external-name':False})
            mutant_overlay=case/'mutant-overlay.json';mutant_overlay.write_text(json.dumps(mapping))
            mutant=case/('skipped-profile.exe' if sys.platform=='win32' else 'skipped-profile')
            run(name+'-mutation-compile',flags+['-ivfsoverlay',str(mutant_overlay),*sources,'-o',str(mutant)])
            detected=subprocess.run([str(mutant),*images,str(prom),str(config_path)],capture_output=True,text=True)
            (case/'mutation.log').write_text(detected.stdout+detected.stderr)
            if detected.returncode!=1 or 'FAIL ' not in detected.stderr:
                raise RuntimeError('Skipped profile guard must fail an assertion, not crash or pass')
            mutations.append({'name':'skip-stage4-profile','compiled':True,'detected':True})
            print('PASS compiled skipped-NVIDIA-profile guard mutation detected',flush=True)
            # Keep the valid captured graph intact; only the generated count differs.
            # The production gate must reject before EDID/NVIDIA stops or decode.
            count_source=case/'count-refusal.c'
            count_source.write_text(r"""#include "test_full.c"
int main(int argc,char **argv) {
  Check(argc==5,"count test requires two driver, PROM and PCI fixtures");
  LoadDriverFixture(argv[1],MouseMemory,sizeof(MouseMemory));
  LoadDriverFixture(argv[2],NvMemory,sizeof(NvMemory));
  FILE *f=fopen(argv[3],"rb");
  Check(f && fread(PromMemory,1,sizeof(PromMemory),f)==sizeof(PromMemory),"count test PROM read");fclose(f);
  f=fopen(argv[4],"rb");
  Check(f && fread(InitialFullConfig,1,sizeof(InitialFullConfig),f)==sizeof(InitialFullConfig),"count test PCI read");fclose(f);
  DecodeTests();
  Check(RunFull(0)==EFI_ACCESS_DENIED && Calls==2 && !EnableCalls && !ClaimCalls,
    "generated child-count mismatch blocks EDID/NVIDIA stop, decode and claim");
  puts("PASS generated child-count mismatch refused before EDID/NVIDIA stop, decode and claim");
  return 0;
}
""",encoding='ascii')
            count_flags=flags+['-I',str(BOOT)]
            count_sources=[str(count_source),*sources[1:]]
            count_guard='if(children!=GU_LOCAL_CHILD_COUNT)return EFI_ACCESS_DENIED;'
            if source.count(count_guard)!=1:raise RuntimeError('Child-count guard mutation no longer matches source')
            first_count_mapping=None
            for wrong_count in (children-1,children+1):
                if not 1<=wrong_count<=4:continue
                expected=f'#define GU_LOCAL_CHILD_COUNT {children}\n'
                text=header.read_text()
                if text.count(expected)!=1:raise RuntimeError('Generated count header is not unique')
                wrong_header=case/f'profile-count-{wrong_count}.h'
                wrong_header.write_text(text.replace(expected,f'#define GU_LOCAL_CHILD_COUNT {wrong_count}\n'))
                count_mapping=json.loads(overlay.read_text())
                count_mapping['roots'][0]['external-contents']=str(wrong_header)
                count_overlay=case/f'count-{wrong_count}-overlay.json'
                count_overlay.write_text(json.dumps(count_mapping))
                if first_count_mapping is None:first_count_mapping=count_mapping
                count_exe=case/(f'count-{wrong_count}.exe' if sys.platform=='win32' else f'count-{wrong_count}')
                run(name+f'-count-{wrong_count}-compile',count_flags+['-ivfsoverlay',str(count_overlay),*count_sources,'-o',str(count_exe)])
                result=run(name+f'-count-{wrong_count}',[str(count_exe),*images,str(prom),str(config_path)])
                count_refusals.append({'case':name,'observed_children':children,'generated_children':wrong_count,'result':result})
                print(result,flush=True)
            count_broken=case/'full-release-skipped-count.c'
            count_broken.write_text(source.replace(count_guard,'/* intentionally removed for host mutation test */'))
            first_count_mapping['roots'].append({'type':'file','name':str(BOOT/'full-release.c'),
                'external-contents':str(count_broken),'use-external-name':False})
            count_mutation_overlay=case/'count-mutation-overlay.json'
            count_mutation_overlay.write_text(json.dumps(first_count_mapping))
            count_mutant=case/('skipped-count.exe' if sys.platform=='win32' else 'skipped-count')
            run(name+'-count-mutation-compile',count_flags+['-ivfsoverlay',str(count_mutation_overlay),*count_sources,'-o',str(count_mutant)])
            detected=subprocess.run([str(count_mutant),*images,str(prom),str(config_path)],capture_output=True,text=True)
            (case/'count-mutation.log').write_text(detected.stdout+detected.stderr)
            if detected.returncode!=1 or 'FAIL ' not in detected.stderr or 'generated child-count mismatch' not in detected.stderr:
                raise RuntimeError('Removed child-count guard must fail its refusal assertion, not crash or pass')
            mutations.append({'name':'skip-generated-child-count','compiled':True,'detected':True})
            print('PASS compiled skipped-generated-child-count guard mutation detected',flush=True)
        if bus==1 and children==1 and command==2 and memory!=0x5ff4:
            for index,image in enumerate(images):
                for length in (0,2,63,Path(image).stat().st_size-1,Path(image).stat().st_size+1):
                    damaged=case/f'bad-image-{index}-{length}.bin';damaged.write_bytes(bytes(length))
                    arguments=images.copy();arguments[index]=str(damaged)
                    refused=subprocess.run([str(exe),*arguments,str(prom),str(config_path)],capture_output=True,text=True)
                    if refused.returncode!=1 or 'captured loaded driver image size mismatch' not in refused.stderr:
                        raise RuntimeError('Malformed capture did not fail safely: '+str(damaged))
                    image_refusals.append({'case':name,'image':index,'bytes':length,'exit':refused.returncode})
        if no_edid and children == 1 and command == 2 and memory != 0x5ff4:
            probe = case / 'probe-report.txt'
            # Exercise the actual alternate 40/48 layout; test_checks retains its
            # historical 60/68/78 assertions in a separate synthetic fixture.
            probe.write_text(''.join(f'config_offset=0x{i*4:x}\nvalue=0x{value:08x}\n' for i,value in enumerate(config)))
            for job, inputs, arguments in (
                ('checks', [str(ROOT / 'internal-boot/unlock/tests/test_checks.c'), str(ROOT / 'internal-boot/unlock/checks.c')], [str(probe)]),
                ('port', [str(ROOT / 'internal-boot/unlock/tests/test_port.c'), str(ROOT / 'internal-boot/unlock/port.c')], [])):
                binary = case / (job + ('.exe' if sys.platform == 'win32' else ''))
                run(name + '-' + job + '-compile', flags + ['-ivfsoverlay', str(overlay), '-DGU_HOST_WRITE_TEST', *inputs, '-o', str(binary)])
                result = run(name + '-' + job, [str(binary), *arguments])
                child_checks.append({'case': name, 'job': job, 'result': result})
                print(name + ': ' + result, flush=True)
    (out / 'summary.json').write_text(json.dumps({'synthetic_only': True, 'hardware_access': False,
                                                 'selection': {'card': args.card, 'children': args.children},
                                                 'mutations':mutations,
                                                 'count_refusals':count_refusals,
                                                 'cases': summaries, 'child_checks': child_checks,
                                                 'image_refusals':image_refusals}, indent=2))


if __name__ == '__main__':
    main()
