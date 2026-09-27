import unittest
from category_highlight_regions import weight_at


class CategoryLandmarksTest(unittest.TestCase):
    def test_chest_includes_nipple_region_and_lower_pectoral_border(self):
        for x in (-.10, .10):
            self.assertGreater(weight_at('chest', x, -.08, 1.245), .95)
        self.assertLess(weight_at('chest', .08, -.08, 1.185), .01)
        self.assertLess(weight_at('chest', .23, -.03, 1.38), .01)
        self.assertEqual(weight_at('chest', .10, .08, 1.30), 0)

    def test_shoulder_covers_cap_not_neck_or_lower_upper_arm(self):
        self.assertGreater(weight_at('shoulders', .20, -.03, 1.445), .95)
        self.assertGreater(weight_at('shoulders', .25, -.03, 1.39), .95)
        self.assertLess(weight_at('shoulders', .05, -.03, 1.46), .01)
        self.assertLess(weight_at('shoulders', .26, -.03, 1.24), .01)

    def test_arm_starts_below_shoulder_and_stops_before_hand(self):
        self.assertGreater(weight_at('arms', .224, -.03, 1.305), .95)
        self.assertGreater(weight_at('arms', .25, -.03, 1.23), .95)
        self.assertGreater(weight_at('arms', .293, -.03, 1.06), .95)
        self.assertLess(weight_at('arms', .21, -.03, 1.445), .01)
        self.assertLess(weight_at('arms', .32, -.03, .94), .01)
        self.assertLess(weight_at('arms', .10, -.08, 1.22), .01)

    def test_left_right_are_identical(self):
        for category in ('chest', 'shoulders', 'arms'):
            for x,z in ((.1,1.25),(.2,1.44),(.23,1.30),(.30,1.05)):
                self.assertEqual(weight_at(category,x,-.04,z),weight_at(category,-x,-.04,z))


if __name__ == '__main__':
    unittest.main()
