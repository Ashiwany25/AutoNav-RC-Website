import json
import unittest
from mapping.teach_mode import TeachModeMapper
from mapping.range_mapper import RangeGridMapper, RangeReading
from hardware.wheel_odometry import WheelCalibration
from hardware.heading_fusion import HeadingMeasurement
from hardware.localization_pipeline import LocalizationPipeline


def sensor(seq, l, r, *, front=1000, estop=True):
    return json.dumps(dict(type='SENSOR', seq=seq, enc_l=l, enc_r=r,
                           front_mm=front, battery_mv=7400,
                           estop_closed=estop), separators=(',', ':')).encode('ascii')


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.grid = TeachModeMapper(12, 12, 1)
        self.pipeline = LocalizationPipeline(
            WheelCalibration(.04, .2, 100), RangeGridMapper(self.grid, max_range_m=4))
        self.pipeline.decoder.clock = lambda: self.now
        self.now = 10.0

    def test_wheel_only_pose_is_not_trusted_global_localization(self):
        result = self.pipeline.ingest(sensor(1, 0, 0), now=self.now)
        self.assertFalse(result.trustworthy)

    def test_valid_range_updates_map(self):
        self.pipeline.odometry.reset(pose=__import__('hardware.wheel_odometry', fromlist=['Pose2D']).Pose2D(2.5,2.5,0))
        self.pipeline.ingest(sensor(1, 0, 0), now=self.now, ranges=[RangeReading(0,2,True)])
        self.assertEqual(self.grid.grid[2][4], 1)

    def test_open_estop_rejected(self):
        with self.assertRaises(ValueError):
            self.pipeline.ingest(sensor(1, 0, 0, estop=False), now=self.now)

    def test_replay_sequence_rejected(self):
        self.pipeline.ingest(sensor(1,0,0), now=self.now)
        self.now += .1
        with self.assertRaises(ValueError):
            self.pipeline.ingest(sensor(1,0,0), now=self.now)

    def test_heading_fusion_calibrated(self):
        self.pipeline.ingest(sensor(1,0,0), now=self.now,
                             heading=HeadingMeasurement(.1,self.now,1))
        self.assertAlmostEqual(self.pipeline.odometry.pose.heading_rad, .02, places=4)
