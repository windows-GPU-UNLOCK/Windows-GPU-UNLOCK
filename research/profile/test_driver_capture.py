"""Synthetic captured-file integration checks; no firmware/hardware execution."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
HERE = Path(__file__).resolve().parent
def load(name, path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
review=load('driver_review',HERE/'review-driver-capture.py')
pe=load('pe_fixture',HERE/'test_pe_bounds.py')

class ReviewTests(unittest.TestCase):
    def test_existing_file_fingerprints_and_refusals(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            image=pe.image()
            (folder/'IMG00.BIN').write_bytes(image)
            text=('binding handle=0x1 image=0x1 version=0x60010 stop=0x100290\n'
                  'img base=0x100000\nimg size=0x3000\nimg dump index=00\n'
                  'img-path-node raw=')
            # A UEFI filepath node with the exact known nvgop name.
            payload=('nvgop-ga1xx'+'\0').encode('utf-16le')
            node=bytes([4,4])+ (4+len(payload)).to_bytes(2,'little')+payload
            text += node.hex()+'\nimg-path-node raw=7fff0400\nhandles status=0x0\ncapture-complete=1\n'
            diag=folder/'DIAG00.TXT';diag.write_text(text,encoding='utf-8')
            before=diag.read_bytes(),(folder/'IMG00.BIN').read_bytes()
            r=review.review(folder)
            self.assertEqual(r['status'],'observed')
            self.assertEqual(r['drivers'][0]['status'],'observed')
            self.assertFalse(r['drivers'][0]['listed_nvgop_code'])
            self.assertEqual(r['drivers'][0]['code_bytes'],1024)
            self.assertFalse(r['write_eligible'])
            self.assertNotIn(tmp,json.dumps(r))
            self.assertEqual(before,(diag.read_bytes(),(folder/'IMG00.BIN').read_bytes()))
            (folder/'IMG00.BIN').write_bytes(b'bad')
            self.assertEqual(review.review(folder)['drivers'][0]['status'],'invalid-image')
            (folder/'IMG00.BIN').unlink()
            self.assertEqual(review.review(folder)['drivers'][0]['status'],'missing-image')
            diag.write_text(text.replace('capture-complete=1','capture-complete=0'),encoding='utf-8')
            self.assertEqual(review.review(folder)['status'],'incomplete')
            diag.write_text(text.replace('handles status=0x0',text.split('handles status=0x0')[0]),encoding='utf-8')
            self.assertEqual(review.review(folder)['status'],'invalid-bindings')
    def test_empty_and_private_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(review.review(Path(tmp))['status'],'unavailable')
            (Path(tmp)/'DIAG00.TXT').write_bytes(b'\xffPRIVATE')
            r=review.review(Path(tmp))
            self.assertEqual(r['status'],'invalid-input')
            self.assertNotIn('PRIVATE',json.dumps(r))

if __name__=='__main__':unittest.main()
