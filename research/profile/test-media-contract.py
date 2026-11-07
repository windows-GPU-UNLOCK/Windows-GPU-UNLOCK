"""Compile the production media path helper into a RAM-only native test, not EFI."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = r'''
#include "media.h"
#include <stdio.h>
#include <string.h>
typedef struct {HARDDRIVE_DEVICE_PATH hd;EFI_DEVICE_PATH_PROTOCOL end;} DISK;
static int count,failed;
#define CHECK(x) do{count++;if(!(x))failed++;}while(0)
static void disk(DISK *p,const EFI_GUID *g){
 memset(p,0,sizeof(*p));p->hd.Header.Type=MEDIA_DEVICE_PATH;p->hd.Header.SubType=MEDIA_HARDDRIVE_DP;
 p->hd.Header.Length[0]=sizeof(HARDDRIVE_DEVICE_PATH);p->hd.PartitionSize=100;
 p->hd.MBRType=2;p->hd.SignatureType=2;memcpy(p->hd.Signature,g,16);
 p->end.Type=END_DEVICE_PATH_TYPE;p->end.SubType=END_ENTIRE_DEVICE_PATH_SUBTYPE;p->end.Length[0]=4;
}
int main(void){
 DISK internal,windows;disk(&internal,&GuInternalPartition);disk(&windows,&GuWindowsPartition);
 BOOLEAN usb=TRUE,match=FALSE;
 CHECK(GuInspectPath(&internal.hd.Header,&GuInternalPartition,NULL,&usb,&match) && !usb && match);
 CHECK(!GuAllowedMediaPath(&internal.hd.Header,FALSE));
 CHECK(GuAllowedMediaPath(&internal.hd.Header,TRUE));
 CHECK(!GuAllowedMediaPath(&windows.hd.Header,TRUE));
 CHECK(!GuAllowedMediaPath(&windows.hd.Header,FALSE));
 CHECK(GuPathIsPartition(&windows.hd.Header,&GuWindowsPartition));
 struct {USB_DEVICE_PATH node;EFI_DEVICE_PATH_PROTOCOL end;} path={0};
 path.node.Header.Type=MESSAGING_DEVICE_PATH;path.node.Header.SubType=MSG_USB_DP;
 path.node.Header.Length[0]=sizeof(USB_DEVICE_PATH);path.end=internal.end;
 CHECK(GuAllowedMediaPath(&path.node.Header,FALSE));
 path.end.SubType=END_INSTANCE_DEVICE_PATH_SUBTYPE;
 CHECK(!GuAllowedMediaPath(&path.node.Header,FALSE));
 path.end=internal.end;path.node.Header.Length[0]=3;
 CHECK(!GuAllowedMediaPath(&path.node.Header,FALSE));
 CHECK(!GuAllowedMediaPath(NULL,FALSE));
 printf("%d production media-path checks; failures=%d. Native RAM only, no EFI/firmware/GPU.\n",count,failed);
 return failed?1:0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--clang', default='clang')
    args = parser.parse_args()
    out = Path(tempfile.mkdtemp(prefix='media-contract-'))
    config = '#define GU_INTERNAL_PARTITION_INITIALIZER {1,0,0,{0}}\n#define GU_WINDOWS_PARTITION_INITIALIZER {2,0,0,{0}}\n'
    (out/'graph-platform-config.h').write_text(config)
    (out/'platform-config.h').write_text(config)
    c = out/'test.c';c.write_text(SOURCE);exe = out/'test.exe'
    command = [args.clang, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-fshort-wchar',
               '-DGU_GRAPH_ONLY', '-DGU_DIAGNOSTIC_ONLY', '-I', str(out), '-I', str(ROOT/'internal-boot/boot'),
               '-I', str(ROOT/'deps/edk2/MdePkg/Include'), '-I', str(ROOT/'deps/edk2/MdePkg/Include/X64'), str(c), '-o', str(exe)]
    subprocess.run(command, check=True);subprocess.run([str(exe)], check=True)


if __name__ == '__main__': main()
