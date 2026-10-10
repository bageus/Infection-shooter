"""Guard screen extraction after atlas materials merge dual-monitor surfaces."""
import unittest
from build_display_surfaces import extract, PROFILES


class DisplaySurfacesTests(unittest.TestCase):
    def test_merged_dual_monitors_exclude_bezels_and_supports(self):
        for name in ('05_monitor3_server_destructible', '05_monitor4_server_destructible'):
            with self.subTest(model=name):
                screens = extract(name, PROFILES[name])['screens']
                self.assertEqual(len(screens), 2)
                for screen in screens:
                    short, long = sorted(screen['size'])
                    self.assertAlmostEqual(short, .3877718, places=5)
                    self.assertAlmostEqual(long, .6652580, places=5)
                    self.assertAlmostEqual(screen['center'][2], .0070914, places=5)
                self.assertGreater(abs(screens[0]['center'][1] - screens[1]['center'][1]), .4)

    def test_display_profiles_cover_all_authored_devices(self):
        for name, profile in PROFILES.items():
            with self.subTest(model=name):
                screens = extract(name, profile)['screens']
                self.assertEqual(len(screens), 2 if '_server_' in name else 1)
                self.assertTrue(all(min(screen['size']) > .1 for screen in screens))


if __name__ == '__main__':
    unittest.main()
