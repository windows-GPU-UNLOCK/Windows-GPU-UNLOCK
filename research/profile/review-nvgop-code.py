"""Read saved NVIDIA image identity with shared parsers; never execute it."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('nvgop_review_profile',HERE/'make-profile.py')
mp=importlib.util.module_from_spec(spec);spec.loader.exec_module(mp)

def review(text,folder,envelope):
    bindings=mp.parse_bindings(text.splitlines())
    if len(bindings)>512:raise ValueError('Binding bound')
    candidates=[b for b in bindings if b['file']==('name',mp.NVGOP_NAME)]
    if len(candidates)!=1:raise ValueError('Need unique NVIDIA binding')
    nv=candidates[0]
    if type(nv.get('dump')) is not int or not 0<=nv['dump']<=99:raise ValueError('Dump index')
    image=folder/f'IMG{nv["dump"]:02d}.BIN'
    if image.is_symlink() or not image.is_file() or not 0<image.stat().st_size<=mp.IMAGE_MAX:
        raise ValueError('Image bounds')
    raw=image.read_bytes()
    code=mp.code_hash(folder,nv,mp.NVGOP_TEXT_RVA)
    version=f'{nv["version"]:x}'
    matches=[{'family':c['family'],'chip':c['chip']} for c in envelope['chips']
        if any(x['version']==version and x['text_sha256']==code['sha256'] for x in c['nvgop'])]
    return {'version':version,'image_bytes':len(raw),'image_sha256':hashlib.sha256(raw).hexdigest(),
        'code_rva':mp.NVGOP_TEXT_RVA,'code_bytes':code['bytes'],'code_sha256':code['sha256'],
        'stop_rva':nv['stop']-nv['base'],'matching_family_code_entries':matches}

def run(folder):
    if not folder.is_dir() or folder.is_symlink():raise ValueError('Folder')
    paths=sorted(p for p in folder.iterdir() if re.fullmatch(r'DIAG[0-9]{2}\.TXT',p.name))
    if not 1<=len(paths)<=16:raise ValueError('Capture count')
    envelope=json.loads((HERE/'proven.json').read_text(encoding='utf-8'))
    rows=[]
    for p in paths:
        if p.is_symlink() or not p.is_file() or p.stat().st_size>4*1024*1024:raise ValueError('Text bounds')
        raw=p.read_bytes();row=review(raw.decode('utf-8-sig').replace('\r\n','\n'),folder,envelope)
        rows.append({'capture':p.name,'capture_sha256':hashlib.sha256(raw).hexdigest(),**row})
    return {'test':'existing-nvgop-code-v1','envelope_sha256':hashlib.sha256((HERE/'proven.json').read_bytes()).hexdigest(),
        'captures':rows,'code_only':True,'hardware_verified':False,'driver_release_verified':False,'write_eligible':False}

if __name__=='__main__':
    try:print(json.dumps(run(Path(sys.argv[1]))))
    except Exception:
        print('Existing NVIDIA code review stopped. Preserve originals; no new capture, code execution or guard edits.',file=sys.stderr)
        sys.exit(1)
