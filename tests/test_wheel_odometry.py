import math
import unittest
from hardware.sensor_telemetry import Telemetry
from hardware.wheel_odometry import Pose2D, WheelCalibration, WheelOdometry


class WheelOdometryTests(unittest.TestCase):
    def setUp(self):
        self.cal = WheelCalibration(wheel_radius_m=0.05, wheel_base_m=0.2,
                                    ticks_per_revolution=1000, maximum_ticks_per_sample=2000)
        self.odom = WheelOdometry(self.cal)

    def packet(self, seq, left, right, t, *, estop=True):
        return Telemetry(seq, left, right, 600, 7400, estop, t)

    def test_baseline_no_motion(self):
        self.assertEqual(self.odom.update(self.packet(1, 50, 50, 1), now=1), Pose2D())

    def test_straight_forward(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        pose = self.odom.update(self.packet(2, 1000, 1000, 1.1), now=1.1)
        self.assertAlmostEqual(pose.x_m, 2 * math.pi * .05)
        self.assertAlmostEqual(pose.y_m, 0)
        self.assertAlmostEqual(pose.heading_rad, 0)

    def test_straight_backward(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        self.assertLess(self.odom.update(self.packet(2, -100, -100, 1.1), now=1.1).x_m, 0)

    def test_turn_in_place(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        pose = self.odom.update(self.packet(2, -100, 100, 1.1), now=1.1)
        self.assertAlmostEqual(pose.x_m, 0)
        self.assertAlmostEqual(pose.y_m, 0)
        self.assertGreater(pose.heading_rad, 0)

    def test_stale_reading_rejected_without_state_change(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        with self.assertRaises(ValueError):
            self.odom.update(self.packet(2, 100, 100, 1.1), now=2)
        self.assertEqual(self.odom.pose, Pose2D())

    def test_duplicate_sequence_rejected(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        with self.assertRaises(ValueError):
            self.odom.update(self.packet(1, 100, 100, 1.1), now=1.1)

    def test_rollback_timestamp_rejected(self):
        self.odom.update(self.packet(1, 0, 0, 1.1), now=1.1)
        with self.assertRaises(ValueError):
            self.odom.update(self.packet(2, 10, 10, 1.0), now=1.1)

    def test_encoder_jump_rejected_no_commit(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        with self.assertRaises(ValueError):
            self.odom.update(self.packet(2, 2001, 0, 1.1), now=1.1)
        self.assertEqual(self.odom.last_sample.sequence, 1)

    def test_estop_rejected(self):
        with self.assertRaises(ValueError):
            self.odom.update(self.packet(1, 0, 0, 1, estop=False), now=1)

    def test_bad_calibration_rejected(self):
        with self.assertRaises(ValueError):
            WheelCalibration(0, .2, 1000)
        with self.assertRaises(ValueError):
            WheelCalibration(.05, .2, True)

    def test_reset_rebaselines(self):
        self.odom.update(self.packet(1, 0, 0, 1), now=1)
        self.odom.reset(pose=Pose2D(1, 2, math.pi))
        self.assertIsNone(self.odom.last_sample)
        self.assertAlmostEqual(abs(self.odom.pose.heading_rad), math.pi)
        self.assertEqual(self.odom.update(self.packet(1, 900, 900, 1.1), now=1.1).x_m, 1)

    def test_heading_normalized(self):
        odom = WheelOdometry(self.cal, pose=Pose2D(0, 0, 10 * math.pi))
        self.assertAlmostEqual(odom.pose.heading_rad, 0)


if __name__ == '__main__':
    unittest.main()
