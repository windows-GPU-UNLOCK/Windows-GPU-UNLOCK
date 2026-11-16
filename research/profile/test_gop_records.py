import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('gop', Path(__file__).with_name('review-gop-records.py'))
m = importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
# Reported metadata transcribed into the proposed diagnostic syntax, not a raw hardware log.
ROW = 'GOPDIAG after-reconnect: [0] handle=0x1234 target=1 max_mode=14 mode=15 fb_base=0 fb_size=0 hres=2560 vres=1440\n'


class Tests(unittest.TestCase):
    def test_reported_present_gop_is_not_missing_handle(self):
        r = m.review(ROW)
        self.assertEqual(r['observations'][0]['classification'], 'present-without-framebuffer')
        self.assertFalse(r['observations'][0]['mode_index_in_range'])
        self.assertFalse(r['set_mode_authorized'])
        self.assertFalse(r['ancestry_independently_verified'])
        self.assertNotIn('1234', str(r))

    def test_live_partial_and_other_target_do_not_authorize_recovery(self):
        for change, value in [('fb_base=0 fb_size=0', 'fb_base=0x1000 fb_size=0x2000'),
                              ('fb_base=0', 'fb_base=0x1000'), ('target=1', 'target=0')]:
            r = m.review(ROW.replace(change, value))
            self.assertFalse(r['write_eligible'])
            self.assertFalse(r['connect_controller_authorized'])

    def test_missing_duplicate_malformed_and_bounds_refuse(self):
        for text in ('', ROW+ROW, ROW.replace('mode=15', 'mode=PRIVATE'), ROW.replace('[0]', '[128]')):
            with self.subTest(text=text[:30]), self.assertRaises(ValueError): m.review(text)


if __name__ == '__main__': unittest.main()
