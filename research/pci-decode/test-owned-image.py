"""Link the research lifecycle with an invalid target; never execute or stage EFI."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--clang',default='clang');p.add_argument('--lld-link',default='lld-link')
    p.add_argument('--output',type=Path,required=True);p.add_argument('--stack-mutations',action='store_true')
    p.add_argument('--restore',action='store_true',help='Retain research MEMORY restore APIs; never execute')
    args=p.parse_args();out=args.output.resolve()
    if out.exists():p.error('Output must be a new directory')
    out.mkdir(parents=True)
    entry=out/'entry.c'
    extra=('static GU_DS_EFI_CONTEXT RestoreContext;static GU_DR_TRANSACTION RestoreTransaction;\n'
        'static GU_DS_SNAPSHOT Baseline;static GU_DS_EFI_BINDING Pins[2];\n'
        'static EFI_STATUS (*volatile InitRestore)(GU_DS_EFI_CONTEXT *,EFI_BOOT_SERVICES *,EFI_HANDLE,const GU_DS_EFI_BINDING *,UINTN,const GU_DS_SNAPSHOT *,BOOLEAN (*)(VOID *,const char *),VOID *)=GuDsEfiInitializeRestore;\n'
        'static GU_DR_RESULT (*volatile Restore)(GU_DS_EFI_CONTEXT *,GU_DR_TRANSACTION *)=GuDsEfiRestoreRun;\n') if args.restore else ''
    if args.restore:
        extra+=('static GU_DS_CAPTURE PostCapture;\n'
            'static EFI_STATUS (*volatile CaptureAfter)(GU_DS_CAPTURE *,EFI_BOOT_SERVICES *,const GU_DS_CAPTURE_TARGET *,const GU_DS_SNAPSHOT *)=GuDsEfiCaptureAfterStop;\n'
            'static EFI_STATUS (*volatile CaptureReleased)(GU_DS_CAPTURE *,EFI_BOOT_SERVICES *,const GU_DS_CAPTURE_TARGET *,const GU_DS_SNAPSHOT *)=GuDsEfiCaptureReleasedMismatch;\n')
        extra+=('static GU_DS_SNAPSHOT ActualAfter;static GU_DS_RELEASE_PLAN ReleasePlan;\n'
            'static EFI_STATUS (*volatile InitReleased)(GU_DS_EFI_CONTEXT *,EFI_BOOT_SERVICES *,EFI_HANDLE,const GU_DS_EFI_BINDING *,UINTN,const GU_DS_SNAPSHOT *,const GU_DS_SNAPSHOT *,const GU_DS_RELEASE_PLAN *,BOOLEAN (*)(VOID *,const char *),VOID *)=GuDsEfiInitializeReleasedRestore;\n')
    dispatch=(' if(((UINTN)image)&1)return InitRestore(&RestoreContext,table->BootServices,image,Pins,0,&Baseline,RejectLog,NULL);\n'
        ' if(((UINTN)image)&2)return Restore(&RestoreContext,&RestoreTransaction)==GU_DR_INVALID?EFI_UNSUPPORTED:EFI_ABORTED;\n') if args.restore else ''
    if args.restore:dispatch+=' if(((UINTN)image)&4)return CaptureAfter(&PostCapture,table->BootServices,&Target,&Baseline);\n'
    if args.restore:dispatch+=' if(((UINTN)image)&8)return CaptureReleased(&PostCapture,table->BootServices,&Target,&Baseline);\n'
    if args.restore:dispatch+=' if(((UINTN)image)&16)return InitReleased(&RestoreContext,table->BootServices,image,Pins,0,&Baseline,&ActualAfter,&ReleasePlan,RejectLog,NULL);\n'
    entry.write_text('/* Invalid-target link fixture; never execute or install. */\n'
        '#include "efi-owned.h"\nstatic GU_DO_TRANSACTION Transaction;\nstatic GU_DS_CAPTURE_TARGET Target;\n'
        'static BOOLEAN RejectLog(VOID *c,const char *e){(void)c;(void)e;return FALSE;}\n'
        'static GU_DO_RESULT (*volatile Run)(GU_DO_TRANSACTION *,EFI_BOOT_SERVICES *,EFI_HANDLE,const GU_DS_CAPTURE_TARGET *,BOOLEAN (*)(VOID *,const char *),VOID *)=GuDsOwnedRun;\n'
        +extra+
        'EFI_STATUS EFIAPI efi_main(EFI_HANDLE image,EFI_SYSTEM_TABLE *table){\n'
        +dispatch+
        ' return Run(&Transaction,table->BootServices,image,&Target,RejectLog,NULL)==GU_DO_INVALID?EFI_UNSUPPORTED:EFI_ABORTED;\n}\n')
    flags=[args.clang,'-target','x86_64-pc-windows-msvc','-std=c11','-ffreestanding','-fno-builtin',
        '-fno-stack-protector','-mno-red-zone','-fshort-wchar','-Os','-Wall','-Wextra','-Werror','-fstack-usage',
        '-I',str(HERE),'-I',str(ROOT/'deps/edk2/MdePkg/Include'),'-I',str(ROOT/'deps/edk2/MdePkg/Include/X64')]
    sources=[HERE/(name+'.c') for name in ('efi-owned','efi-capture','efi-adapter','decode-sync','snapshot')]
    sources += [ROOT/'internal-boot/efi_runtime.c',entry]
    if args.restore:
        flags.extend(('-DGU_DS_POST_STOP_RESTORE=1','-DGU_DS_POST_STOP_CAPTURE=1'));sources.append(HERE/'stop-transition.c')

    def build(folder,inputs):
        objects=[]
        for source in inputs:
            obj=folder/(source.stem+'.obj')
            result=subprocess.run([*flags,'-c',str(source),'-o',str(obj)],capture_output=True,text=True,timeout=30)
            (folder/(source.stem+'-compile.log')).write_text(result.stdout+result.stderr)
            if result.returncode:raise RuntimeError('Compile failed: '+source.name)
            if not args.restore and source.name=='efi-adapter.c':
                for name in (b'GuDsEfiInitializeRestore',b'GuDsEfiInitializeReleasedRestore',b'GuDsEfiRestoreRun',b'GuDsStopTransition'):
                    if name in obj.read_bytes():raise RuntimeError('Restore symbol in ordinary adapter object')
            objects.append(str(obj))
        image=folder/'owned-link-test.EFI';symbols=folder/'owned-link-test.map'
        linked=subprocess.run([args.lld_link,'/nologo','/nodefaultlib','/subsystem:efi_application','/entry:efi_main',
            '/machine:x64','/base:0','/dynamicbase','/nxcompat','/timestamp:0','/opt:ref','/opt:icf',
            '/map:'+str(symbols),'/out:'+str(image),*objects],capture_output=True,text=True,timeout=30)
        (folder/'link.log').write_text(linked.stdout+linked.stderr)
        frames=[]
        for usage in sorted(folder.glob('*.su')):
            for line in usage.read_text().splitlines():
                name,size,kind=line.split('\t')
                if not size.isdigit() or kind!='static':raise RuntimeError('Unknown/dynamic stack record')
                frames.append({'function':name,'bytes':int(size)})
        if not frames:raise RuntimeError('No compiler stack evidence')
        return linked,image,symbols,frames

    linked,image,symbols,frames=build(out,sources)
    if linked.returncode:raise RuntimeError('Owned lifecycle EFI link failed; see link.log')
    maximum=max(row['bytes'] for row in frames)
    if maximum>2048:raise RuntimeError('Function frame exceeds 2 KiB')
    mapping=symbols.read_text()
    for name in ('GuDsOwnedRun','GuDsEfiCapture','GuDsEfiInitialize','GuDsEfiRun','GuDecodeSync'):
        if not re.search(r'\b'+name+r'\b',mapping):raise RuntimeError('Missing retained lifecycle symbol: '+name)
    if args.restore:
        for name in ('GuDsEfiInitializeRestore','GuDsEfiInitializeReleasedRestore','GuDsEfiRestoreRun','GuDsStopTransition','GuDsEfiCaptureAfterStop','GuDsEfiCaptureReleasedMismatch','GuDsPlanReleasedMismatch'):
            if not re.search(r'\b'+name+r'\b',mapping):raise RuntimeError('Missing restore symbol: '+name)
    if re.search(r'\b(?:__chkstk|GuDsTestCoreWorkspace|GuDsTestAdapterWorkspace)\b',mapping):
        raise RuntimeError('Stack-probe stub or host-only address probe entered image')
    spec=importlib.util.spec_from_file_location('owned_pe_checker',ROOT/'internal-boot/unlock/verify_pe.py')
    checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
    pe=checker.inspect(image,symbols);(out/'pe-verification.json').write_text(json.dumps(pe,indent=2))
    # Address-export test probes cannot even compile under freestanding flags.
    for name in ('decode-sync','efi-adapter'):
        result=subprocess.run([*flags,'-DGU_DS_HOST_WORKSPACE_TEST','-fsyntax-only',str(HERE/(name+'.c'))],capture_output=True,text=True,timeout=30)
        (out/(name+'-host-guard.log')).write_text(result.stdout+result.stderr)
        if result.returncode==0 or 'exclusively for hosted RAM tests' not in result.stderr:
            raise RuntimeError('Host-only workspace address probe guard failed')
    mutants=[]
    if args.stack_mutations:
        changes={
            'core-automatic-snapshots':('decode-sync.c',[
                ('  Active.Ops=*ops;Active.Pin=*expected;',
                 '  GU_DS_SNAPSHOT localPin=*expected,localNow;Active.Ops=*ops;'),
                ('const GU_DS_SNAPSHOT *pin=&Active.Pin;', 'const GU_DS_SNAPSHOT *pin=&localPin;'),
                ('GU_DS_SNAPSHOT *now=&Active.Now;', 'GU_DS_SNAPSHOT *now=&localNow;')]),
            'adapter-automatic-context':('efi-adapter.c',[
                ('static GU_DS_EFI_CONTEXT ActiveAdapter;\n',''),
                ('GU_DS_EFI_CONTEXT *active=&ActiveAdapter;*active=*c;c->Busy=TRUE;',
                 'GU_DS_EFI_CONTEXT localActive;GU_DS_EFI_CONTEXT *active=&localActive;*active=*c;c->Busy=TRUE;')]),
            'adapter-automatic-read-pair':('efi-adapter.c',[
                ('GU_DS_SNAPSHOT *first=&ReadSnapshots[0],*second=&ReadSnapshots[1];',
                 'GU_DS_SNAPSHOT localFirst,localSecond;GU_DS_SNAPSHOT *first=&localFirst,*second=&localSecond;')]),
            'adapter-automatic-disable-snapshot':('efi-adapter.c',[
                ('GU_DS_SNAPSHOT *now=&DisableSnapshot;', 'GU_DS_SNAPSHOT localNow;GU_DS_SNAPSHOT *now=&localNow;')]),
        }
        if args.restore:
            # The shared global is still used by RestoreRun. Only the ordinary
            # Run is made automatic by this existing negative variant.
            changes['adapter-automatic-context'][1].pop(0)
            changes['restore-automatic-stop-snapshot']=('efi-adapter.c',[
                ('GU_DS_EFI_CONTEXT *a=&ActiveAdapter;*a=*c;a->Busy=FALSE;',
                 'GU_DS_SNAPSHOT RestoreInitial;GU_DS_EFI_CONTEXT *a=&ActiveAdapter;*a=*c;a->Busy=FALSE;')])
        for name,(file,replacements) in changes.items():
            folder=out/name;folder.mkdir();text=(HERE/file).read_text()
            for before,after in replacements:
                if before not in text:raise RuntimeError('Stale stack mutation: '+name)
                text=text.replace(before,after)
            changed=folder/file;changed.write_text(text)
            inputs=[changed if source==HERE/file else source for source in sources]
            failure,_,_,bad_frames=build(folder,inputs)
            if failure.returncode==0 or '__chkstk' not in failure.stdout+failure.stderr or max(r['bytes'] for r in bad_frames)<=4096:
                raise RuntimeError('Automatic workspace did not reproduce stack-probe link failure: '+name)
            mutants.append({'name':name,'compiled':True,'link_rejected':True,'max_frame_bytes':max(r['bytes'] for r in bad_frames)})
    inputs=sources+list(HERE.glob('*.h'))
    summary={'synthetic_invalid_target':True,'hardware_access':False,'efi_executed':False,'staged':False,
        'package_authorized':False,'actuator_sources_linked':True,'restore_opt_in':args.restore,'max_frame_bytes':maximum,'frames':frames,
        'stack_mutations':mutants,'source_sha256':{str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path):hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}}
    (out/'summary.json').write_text(json.dumps(summary,indent=2))
    print(f'PASS owned lifecycle EFI link/PE/import checks; maximum function frame {maximum} bytes; never executed')
    if mutants:print(f'PASS {len(mutants)} automatic-workspace variants compiled, then rejected for __chkstk')


if __name__=='__main__':main()
