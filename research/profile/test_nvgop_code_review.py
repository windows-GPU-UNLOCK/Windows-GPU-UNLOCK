import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
HERE=Path(__file__).resolve().parent

def load(name,path):
    s=importlib.util.spec_from_file_location(name,HERE/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
review=load('nvgop_review','review-nvgop-code.py')
fixture=load('nvgop_pe_fixture','test_compatibility.py')

class CodeReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        rva=review.mp.NVGOP_TEXT_RVA
        self.image=fixture.driver_image(0x4000,rva,0x500)
        (self.root/'IMG00.BIN').write_bytes(self.image)
        name=(review.mp.NVGOP_NAME+'\0').encode('utf-16-le')
        node=bytes([4,4])+int(4+len(name)).to_bytes(2,'little')+name
        self.text=('binding handle=0x1 image=0x2 version=0x6000a stop=0x'+format(0x100000+rva,'x')+'\n'
          'img base=0x100000\nimg size=0x4000\nimg dump index=00\nimg-path-node raw='+node.hex()+'\nimg-path-node raw=7fff0400\n')
        digest=hashlib.sha256(self.image[rva:rva+0x500]).hexdigest()
        self.envelope={'chips':[{'family':'GA102','chip':'b72000a1','nvgop':[{'version':'6000a','text_sha256':digest}]},
            {'family':'GA106','chip':'b76000a1','nvgop':[{'version':'60010','text_sha256':'0'*64}]}]}
    def test_full_identity_and_cross_family_scope(self):
        row=review.review(self.text,self.root,self.envelope)
        self.assertEqual(row['image_sha256'],hashlib.sha256(self.image).hexdigest())
        self.assertEqual(len(row['code_sha256']),64)
        self.assertEqual(row['stop_rva'],review.mp.NVGOP_TEXT_RVA)
        self.assertEqual(row['matching_family_code_entries'],[{'family':'GA102','chip':'b72000a1'}])
    def test_duplicate_missing_truncated_and_stop_outside_refuse(self):
        for text in ('',self.text+self.text,self.text.replace('stop=0x'+format(0x100000+review.mp.NVGOP_TEXT_RVA,'x'),'stop=0x100000')):
            with self.subTest(text=text):
                with self.assertRaises((ValueError,review.mp.Refused)):review.review(text,self.root,self.envelope)
        (self.root/'IMG00.BIN').write_bytes(self.image[:-1])
        with self.assertRaises(review.mp.Refused):review.review(self.text,self.root,self.envelope)
    def test_cli_scope_never_admits_code(self):
        (self.root/'DIAG00.TXT').write_text(self.text)
        row=review.run(self.root)
        for key in ('hardware_verified','driver_release_verified','write_eligible'):self.assertFalse(row[key])
        self.assertNotIn(str(self.root),str(row))
        self.assertTrue(row['code_only'])

if __name__=='__main__':unittest.main()
