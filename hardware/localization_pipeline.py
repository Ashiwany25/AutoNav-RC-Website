"""Strict fusion of validated encoder telemetry, optional calibrated heading and ranges.

The output is a candidate pose, not a globally localized SLAM estimate. Never
use it for physical actuation without confidence and frame calibration.
"""
from hardware.sensor_telemetry import Telemetry, TelemetryDecoder
from hardware.wheel_odometry import WheelOdometry, WheelCalibration, Pose2D
from hardware.heading_fusion import HeadingFusion, HeadingMeasurement
from navigation.localized_planner import PoseEstimate
from mapping.range_mapper import RangeGridMapper, RangeReading


class LocalizationPipeline:
    def __init__(self, calibration: WheelCalibration, mapper: RangeGridMapper):
        if not isinstance(mapper, RangeGridMapper):
            raise TypeError('Invalid range mapper')
        self.decoder = TelemetryDecoder()
        self.odometry = WheelOdometry(calibration)
        self.fusion = HeadingFusion()
        self.mapper = mapper
        self.last_time = None

    def ingest(self, raw: bytes, *, now, heading: HeadingMeasurement | None = None,
               ranges: list[RangeReading] | None = None):
        # No physical motors are controlled in this pipeline.
        sample = self.decoder.decode(raw)
        if not sample.safe_to_move(now=now):
            raise ValueError('Unsafe or stale telemetry: STOP required')
        if self.last_time is not None and now <= self.last_time:
            raise ValueError('Clock replay')
        # Validate heading before mutating odometry where possible.
        if heading is not None:
            if heading.sequence <= self.fusion.last_sequence:
                raise ValueError('Stale heading')
        pose = self.odometry.update(sample, now=now)
        if heading is not None:
            pose = self.fusion.update(pose, heading, now=now)
            self.odometry.pose = pose
        if ranges is not None:
            self.mapper.integrate(pose, ranges)
        self.last_time = now
        # Wheel-only data has no externally established global confidence.
        return PoseEstimate(pose, sample.received_at, trustworthy=False)
