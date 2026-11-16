"""Compile/run actual parent-enabled diagnostic in host RAM; no EFI execution/staging."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parents[2]


def load(name, filename):
    spec=importlib.util.spec_from_file_location(name,ROOT/'research/profile'/filename)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def public_primary(report):
    result=copy.deepcopy(report)
    for row in result['observations']:row.pop('parent_baseline',None)
    return result


def intake(prefix, folder, checker, comparison):
    """Actual producer bytes to bounded checker/schema/comparison, in host RAM."""
    folder.mkdir()
    capture=folder/'DIAG00.TXT'
    envelope=json.loads((ROOT/'research/profile/proven.json').read_text())

    def assess(text):
        capture.write_text(text,encoding='ascii')
        report=checker.check(folder,envelope)
        comparison.validate(json.loads(json.dumps(report)))
        if len(report['observations'])!=1 or not report['observations'][0]['available']:
            raise AssertionError('Actual producer graph was not parsed')
        return report

    def parent(report):return report['observations'][0]['parent_baseline']
    def field(left,right):
        result=comparison.compare(left,right)
        if result['status']!='compared' or result['hardware_tested'] or result['write_eligible']:
            raise AssertionError('Comparison cannot grant eligibility')
        return next(row for row in result['fields'] if row['field']=='parent_baseline')['state']

    checked=[]
    for suffix in ('normal','unsupported','command3','24c9'):
        text=Path(str(prefix)+'.'+suffix+'.TXT').read_bytes().decode('ascii').replace('\r\n','\n')
        # No diagnostic record is fabricated/reformatted by this Python bridge.
        full=assess(text)
        expected='recorded' if suffix=='normal' else 'unavailable'
        if parent(full)['state']!=expected:raise AssertionError((suffix,parent(full)))
        if field(full,full)!=('same' if suffix=='normal' else 'unavailable'):
            raise AssertionError('Missing/failed observations became the same')
        stripped='\n'.join(line for line in text.splitlines() if not line.startswith('parent-baseline'))+'\n'
        if public_primary(full)!=public_primary(assess(stripped)):
            raise AssertionError('Optional producer metadata changed primary assessment')
        if full['hardware_tested'] or full['write_eligible']:raise AssertionError('Hardware approval escaped')
        checked.append(suffix)
        if suffix!='normal':continue
        legacy=copy.deepcopy(full)
        del legacy['observations'][0]['parent_baseline']
        if field(legacy,full)!='unavailable':raise AssertionError('Legacy report inherited a parent baseline')
        rows=text.splitlines()
        device=next(line for line in rows if line.startswith('parent-baseline-device index=0x01 '))
        config=next(line for line in rows if line.startswith('parent-baseline-config index=0x01 '))
        gpu=next(line for line in rows if line.startswith('parent-baseline-device index=0x00 '))
        bus=int(gpu.split(' bus=0x',1)[1][:2],16)
        wrong=gpu.replace(f' bus=0x{bus:02x}',f' bus=0x{bus^1:02x}')
        for damaged in (text.replace(config+'\n',''),text+device+'\n',text.replace(gpu,wrong)):
            bad=assess(damaged)
            if parent(bad)['state']!='invalid' or public_primary(bad)!=public_primary(full):
                raise AssertionError('Malformed optional producer data affected primary admission')
        words=config.split(' words=',1)[1].split()
        for index in (4,11,20):words[index]='cafebabe'
        changed=config.split(' words=',1)[0]+' words='+' '.join(words)+' '
        changed_report=assess(text.replace(config,changed))
        if changed_report!=full:raise AssertionError('Private bridge addresses affected public JSON')
        if 'cafebabe' in json.dumps(changed_report)+json.dumps(comparison.compare(full,changed_report)):
            raise AssertionError('Raw bridge window leaked into shared output')
        # Uninterpreted high attribute bits are omitted from the normalized
        # decode masks. They must never be reprinted as opaque 64-bit numbers.
        high=device.replace('attributes=0x0000000000000700','attributes=0x8000000000000700')
        if assess(text.replace(device,high))!=full:raise AssertionError('Opaque attributes escaped masking')
        checked+=['legacy','missing','duplicate','wrong-bdf','private-bridge-addresses','opaque-attribute-bits']
    return checked


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang',default='clang')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error('Output must be a new directory')
    out.mkdir(parents=True)
    sources=['internal-boot/boot/test_probe_parent.c','internal-boot/boot/probe.c','internal-boot/boot/probe-parent.c',
             'research/pci-decode/efi-capture.c','research/pci-decode/snapshot.c','internal-boot/unlock/sha256.c']
    flags=[args.clang,'-std=c11','-O1','-Wall','-Wextra','-Werror','-D_CRT_SECURE_NO_WARNINGS',
           '-DGU_DIAGNOSTIC_ONLY','-DGU_DIAGNOSTIC_PROBE','-DGU_PROBE_GENERIC','-DGU_PROBE_AUTO_BUS',
           '-DGU_PROBE_PARENT_BASELINE','-I',str(ROOT/'deps/edk2/MdePkg/Include'),'-I',str(ROOT/'deps/edk2/MdePkg/Include/X64')]
    results=[]
    checker=load('parent_producer_checker','check-compatibility.py')
    comparison=load('parent_producer_comparison','compare-compatibility.py')
    for bus in (1,43,255):
        for segment in (0,1,0xffff):
            name=f'bus{bus}-segment{segment}';exe=out/(name+'.exe')
            prefix=out/(name+'-capture')
            for stage,command in (('compile',[*flags,f'-DGU_TEST_PROBE_BUS={bus}',f'-DGU_PARENT_TEST_SEGMENT={segment}',
                                               *[str(ROOT/p) for p in sources],'-o',str(exe)]),('run',[str(exe),str(prefix)])):
                r=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=30)
                (out/(name+'-'+stage+'.log')).write_text(r.stdout+r.stderr)
                if r.returncode:raise RuntimeError(name+' '+stage+': '+(r.stdout+r.stderr)[-2000:])
            checks=intake(prefix,out/(name+'-intake'),checker,comparison)
            results.append({'bus':bus,'segment':segment,'result':r.stdout.strip(),'intake_cases':checks});print(name+': '+r.stdout.strip()+'; intake/schema/comparison passed',flush=True)
    legacy=[]
    common=[args.clang,'-std=c11','-O1','-Wall','-Wextra','-Werror','-D_CRT_SECURE_NO_WARNINGS',
            '-I',str(ROOT/'deps/edk2/MdePkg/Include'),'-I',str(ROOT/'deps/edk2/MdePkg/Include/X64')]
    cases=[('diagnostic','test_diagnostic.c',[])]
    cases += [(p,'test_probe.c',['-DGU_DIAGNOSTIC_PROBE','-DGU_PROFILE_'+p]) for p in
              ('B650M_3090FE','B660M_3070TI','B660M_3090TI','X870_3090TI','B660PLUS_3060')]
    cases += [(p,'test_probe_generic.c',['-DGU_DIAGNOSTIC_ONLY','-DGU_DIAGNOSTIC_PROBE','-DGU_USB_MEDIA','-DGU_PROFILE_'+p])
              for p in ('H610M_3060','PROBE_H610M_3060')]
    cases += [('generic-old','test_probe_generic.c',['-DGU_DIAGNOSTIC_ONLY','-DGU_DIAGNOSTIC_PROBE','-DGU_PROBE_GENERIC','-DGU_PROBE_AUTO_BUS'])]
    for name,source,defines in cases:
        exe=out/(name+'.exe');inputs=[ROOT/'internal-boot/boot'/source]
        if name!='diagnostic':inputs += [ROOT/'internal-boot/boot/probe.c',ROOT/'internal-boot/unlock/sha256.c']
        for stage,command in (('compile',[*common,*defines,*map(str,inputs),'-o',str(exe)]),('run',[str(exe)])):
            r=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=30)
            (out/(name+'-'+stage+'.log')).write_text(r.stdout+r.stderr)
            if r.returncode:raise RuntimeError(name+' '+stage+': '+(r.stdout+r.stderr)[-2000:])
        legacy.append({'case':name,'result':r.stdout.strip()});print(name+': passed',flush=True)
    guards=[]
    for index,bad in enumerate(('-DGU_FULL_UNLOCK','-DGU_UEFI_PORT','-UGU_PROBE_GENERIC')):
        r=subprocess.run([*flags,bad,'-fsyntax-only',str(ROOT/'internal-boot/boot/probe-parent.c')],
                         cwd=ROOT,capture_output=True,text=True,timeout=30)
        (out/f'guard-{index}.log').write_text(r.stdout+r.stderr)
        if r.returncode==0 or 'Parent baseline is restricted' not in r.stderr:raise RuntimeError('Readonly parent compile guard failed')
        guards.append(bad)
    (out/'summary.json').write_text(json.dumps({'hardware_access':False,'efi_executed':False,
        'actual_producer_mocked':True,'cases':results,'legacy':legacy,'compile_guards':guards},indent=2))


if __name__=='__main__':main()
