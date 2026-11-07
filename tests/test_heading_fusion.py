import math
import unittest

from hardware.wheel_odometry import Pose2D
from hardware.heading_fusion import HeadingMeasurement, FusionSettings, HeadingFusion, wrap


class HeadingFusionTests(unittest.TestCase):
    def setUp(self):
        self.fusion = HeadingFusion(FusionSettings(gain=0.25))
        self.pose = Pose2D(1.0, 2.0, 0.0)

    def measurement(self, yaw=0.4, time=1.0, sequence=1):
        return HeadingMeasurement(yaw, time, sequence)

    def test_heading_correction(self):
        p = self.fusion.update(self.pose, self.measurement(), now=1.1)
        self.assertAlmostEqual(p.heading_rad, 0.1)

    def test_xy_not_fabricated(self):
        p = self.fusion.update(self.pose, self.measurement(), now=1.1)
        self.assertEqual((p.x_m, p.y_m), (1, 2))

    def test_wraps_across_pi(self):
        p = self.fusion.update(Pose2D(0, 0, math.pi - .1),
                               self.measurement(-math.pi + .1), now=1.1)
        self.assertAlmostEqual(p.heading_rad, math.pi - .05)

    def test_duplicate_rejected(self):
        self.fusion.update(self.pose, self.measurement(), now=1.1)
        with self.assertRaises(ValueError):
            self.fusion.update(self.pose, self.measurement(), now=1.1)

    def test_out_of_order_timestamp_rejected(self):
        self.fusion.update(self.pose, self.measurement(), now=1.1)
        with self.assertRaises(ValueError):
            self.fusion.update(self.pose, self.measurement(time=.9, sequence=2), now=1.1)

    def test_stale_heading_rejected(self):
        with self.assertRaises(ValueError):
            self.fusion.update(self.pose, self.measurement(), now=1.6)

    def test_future_heading_rejected(self):
        with self.assertRaises(ValueError):
            self.fusion.update(self.pose, self.measurement(), now=.99)

    def test_outlier_rejected_without_state_change(self):
        self.fusion.update(self.pose, self.measurement(), now=1.1)
        old = (self.fusion.last_pose, self.fusion.last_sequence)
        with self.assertRaises(ValueError):
            self.fusion.update(self.pose, self.measurement(2, 1.2, 2), now=1.2)
        self.assertEqual((self.fusion.last_pose, self.fusion.last_sequence), old)

    def test_invalid_gain_rejected(self):
        with self.assertRaises(ValueError):
            FusionSettings(gain=2)

    def test_nonfinite_yaw_rejected(self):
        with self.assertRaises(ValueError):
            self.measurement(float('nan'))

    def test_invalid_odometry_rejected(self):
        with self.assertRaises(ValueError):
            self.fusion.update(Pose2D(float('inf'), 0, 0), self.measurement(), now=1.1)

    def test_reset_allows_new_sequence(self):
        self.fusion.update(self.pose, self.measurement(), now=1.1)
        self.fusion.reset()
        p = self.fusion.update(self.pose, self.measurement(), now=1.1)
        self.assertAlmostEqual(p.heading_rad, .1)


if __name__ == '__main__':
    unittest.main()
