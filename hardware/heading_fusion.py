"""Offline wheel-heading + absolute-heading fusion.

This is not SLAM or a globally accurate pose estimator. An IMU yaw must
already be calibrated and expressed in the same coordinate frame as odometry.
No direct motor commands or navigation decisions are made here.
"""
from dataclasses import dataclass
import math

from hardware.wheel_odometry import Pose2D


def wrap(angle: float) -> float:
    if type(angle) not in (float, int) or not math.isfinite(angle):
        raise ValueError("Heading must be finite")
    return (angle + math.pi) % (2 * math.pi) - math.pi


@dataclass(frozen=True)
class HeadingMeasurement:
    yaw_rad: float
    received_at: float
    sequence: int

    def __post_init__(self):
        wrap(self.yaw_rad)
        if type(self.received_at) not in (int, float) or not math.isfinite(self.received_at) or self.received_at < 0:
            raise ValueError("Invalid sensor timestamp")
        if type(self.sequence) is not int or self.sequence <= 0:
            raise ValueError("Invalid heading sequence")


@dataclass(frozen=True)
class FusionSettings:
    gain: float = 0.2
    max_age_seconds: float = 0.5
    max_disagreement_rad: float = math.radians(60)

    def __post_init__(self):
        if type(self.gain) not in (int, float) or not math.isfinite(self.gain) or not 0 <= self.gain <= 1:
            raise ValueError("gain must be in [0,1]")
        if type(self.max_age_seconds) not in (int, float) or not math.isfinite(self.max_age_seconds) or self.max_age_seconds <= 0:
            raise ValueError("Invalid freshness limit")
        if type(self.max_disagreement_rad) not in (int, float) or not math.isfinite(self.max_disagreement_rad) or not 0 < self.max_disagreement_rad <= math.pi:
            raise ValueError("Invalid disagreement threshold")


class HeadingFusion:
    """Fail-closed fusion. Every accepted measurement must be fresh and newer.

    Rejected sensor data raises ValueError and cannot alter the last output.
    An external controller must treat rejected data as untrusted, not quietly
    continue moving based on this estimate.
    """

    def __init__(self, settings: FusionSettings = FusionSettings()):
        self.settings = settings
        self.last_sequence = 0
        self.last_timestamp = -1.0
        self.last_pose = None

    def update(self, odometry_pose: Pose2D, measurement: HeadingMeasurement, *, now: float) -> Pose2D:
        if not isinstance(odometry_pose, Pose2D) or not isinstance(measurement, HeadingMeasurement):
            raise TypeError("Expected Pose2D and HeadingMeasurement")
        if not all(type(v) in (int, float) and math.isfinite(v) for v in (odometry_pose.x_m, odometry_pose.y_m, odometry_pose.heading_rad)):
            raise ValueError("Nonfinite odometry")
        if type(now) not in (int, float) or not math.isfinite(now):
            raise ValueError("Invalid clock")
        age = now - measurement.received_at
        if age < 0 or age > self.settings.max_age_seconds:
            raise ValueError("Stale or future heading")
        if measurement.sequence <= self.last_sequence or measurement.received_at <= self.last_timestamp:
            raise ValueError("Duplicate or out-of-order heading")
        delta = wrap(measurement.yaw_rad - odometry_pose.heading_rad)
        if abs(delta) > self.settings.max_disagreement_rad:
            raise ValueError("Heading disagreement exceeds safety gate")
        output = Pose2D(odometry_pose.x_m, odometry_pose.y_m,
                        wrap(odometry_pose.heading_rad + self.settings.gain * delta))
        self.last_sequence = measurement.sequence
        self.last_timestamp = measurement.received_at
        self.last_pose = output
        return output

    def reset(self):
        """Explicitly rebaseline after a sensor restart / frame recalibration."""
        self.last_sequence = 0
        self.last_timestamp = -1.0
        self.last_pose = None
