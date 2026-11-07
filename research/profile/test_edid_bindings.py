import importlib.util
from pathlib import Path
import unittest
import uuid

HERE=Path(__file__).resolve().parent
def load(name,file):
    s=importlib.util.spec_from_file_location(name,HERE/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=load('edid_review','review-edid-bindings.py');data=load('edid_data','test_local_topology.py')


class Tests(unittest.TestCase):
    def test_foreign_edid_is_bound_not_absent(self):
        text=data.synthetic_capture(no_edid=False,children=1)
        text=text.replace(uuid.UUID(m.mp.MOUSE_FILE).bytes_le.hex(),uuid.UUID('605ced2c-583b-4171-9311-aa6e146b1a4b').bytes_le.hex())
        text=text.replace('binding handle=0x9 image=0x9 version=0x1 ', 'binding handle=0x9 image=0x9 version=0x10 ')
        r=m.review(text)
        self.assertEqual(r['discovered_by_driver_count'],1)
        self.assertEqual(r['bindings'][0]['version'],16)
        self.assertFalse(r['bindings'][0]['reviewed_mouse_identity_match'])
        self.assertFalse(r['no_edid_driver_authorized'])
        with self.assertRaises(data.mp.Refused): data.analyze(text)

    def test_active_is_not_discovered_and_get_protocol_is_not_owner(self):
        text=data.synthetic_capture(no_edid=False,children=1).replace(m.mp.EDID_DISCOVERED,m.ACTIVE)
        r=m.review(text);self.assertEqual(r['active_by_driver_count'],1);self.assertEqual(r['discovered_by_driver_count'],0)
        self.assertEqual(m.review(data.synthetic_capture(no_edid=True,children=1))['discovered_by_driver_count'],0)

    def test_same_version_peer_image_is_not_the_edid_edge_owner(self):
        # Public metadata transcribed into synthetic records, not owner DIAG.
        text=data.synthetic_capture(no_edid=False,children=1)
        start=text.index('binding handle=0x9 ');end=text.index('handles status=',start)
        binding=text[start:end].replace('version=0x1 ','version=0x10 ')
        mouse=uuid.UUID(m.mp.MOUSE_FILE).bytes_le.hex()
        owner='e1ff8a3d-0a1f-49c2-67d3-930bcaee7798'
        peer='605ced2c-583b-4171-9311-aa6e146b1a4b'
        owner_binding=binding.replace(mouse,uuid.UUID(owner).bytes_le.hex())
        peer_binding=binding.replace('handle=0x9 image=0x9','handle=0x19 image=0x19').replace(mouse,uuid.UUID(peer).bytes_le.hex())
        for records in (owner_binding+peer_binding,peer_binding+owner_binding):
            with self.subTest(peer_first=records.startswith(peer_binding)):
                capture=text[:start]+records+text[end:]
                report=m.review(capture)
                self.assertEqual(report['bindings'],[{'protocol':'discovered','version':16,
                    'file_guid':owner,'reviewed_mouse_identity_match':False}])
                self.assertEqual(report['discovered_by_driver_count'],1)
                self.assertEqual(report['active_by_driver_count'],0)
                self.assertFalse(report['no_edid_driver_authorized'])
                self.assertFalse(report['driver_detach_authorized'])
                with self.assertRaises(data.mp.Refused):data.analyze(capture)

    def test_incomplete_and_ambiguous_refuse(self):
        text=data.synthetic_capture(no_edid=False,children=1)
        for bad in (text.replace('capture-complete=1','capture-complete=0'),text.replace('binding handle=0x9 image=0x9','binding handle=0x99 image=0x9')):
            with self.assertRaises((ValueError,m.mp.Refused)):m.review(bad)


if __name__=='__main__':unittest.main()
