"""Differential-drive encoder odometry for offline testing (NOT safe localization).

Consumes validated hardware.sensor_telemetry.Telemetry packets. Calibration and
on-robot sensor validation are required before using estimates for navigation.
"""
from dataclasses import dataclass
import math
from hardware.sensor_telemetry import Telemetry


def _finite_positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


@dataclass(frozen=True)
class WheelCalibration:
    wheel_radius_m: float
    wheel_base_m: float
    ticks_per_revolution: int
    maximum_ticks_per_sample: int = 3000

    def __post_init__(self):
        if not _finite_positive(self.wheel_radius_m) or not _finite_positive(self.wheel_base_m):
            raise ValueError("Wheel dimensions must be finite and positive")
        if type(self.ticks_per_revolution) is not int or self.ticks_per_revolution <= 0:
            raise ValueError("ticks_per_revolution must be positive")
        if type(self.maximum_ticks_per_sample) is not int or self.maximum_ticks_per_sample <= 0:
            raise ValueError("maximum_ticks_per_sample must be positive")


@dataclass(frozen=True)
class Pose2D:
    x_m: float = 0.0
    y_m: float = 0.0
    heading_rad: float = 0.0


def _normalize(angle):
    return (angle + math.pi) % (2 * math.pi) - math.pi


class WheelOdometry:
    """Estimate a pose from consecutive encoder samples.

    Fail-closed on stale packets, missing E-STOP loop, replay, unrealistic jumps,
    and telemetry timestamp rollback. Does not imply collision avoidance.
    Encoder counters must not roll over during a session; reinitialize explicitly
    after sensor restart. No global coordinate map alignment is assumed.
    """

    def __init__(self, calibration: WheelCalibration, *, pose=Pose2D()):
        if not isinstance(calibration, WheelCalibration) or not isinstance(pose, Pose2D):
            raise TypeError("Expected WheelCalibration and Pose2D")
        if not all(math.isfinite(v) for v in (pose.x_m, pose.y_m, pose.heading_rad)):
            raise ValueError("Initial pose must be finite")
        self.calibration = calibration
        self.pose = Pose2D(pose.x_m, pose.y_m, _normalize(pose.heading_rad))
        self.last_sample = None

    def update(self, packet: Telemetry, *, now: float):
        if not isinstance(packet, Telemetry) or not _finite_positive(now):
            raise ValueError("Invalid telemetry or clock")
        if not packet.is_fresh(now=now):
            raise ValueError("Stale or future telemetry")
        if not packet.estop_closed:
            raise ValueError("E-STOP loop open; odometry update rejected")
        if self.last_sample is None:
            self.last_sample = packet
            return self.pose
        old = self.last_sample
        if packet.sequence <= old.sequence or packet.received_at <= old.received_at:
            raise ValueError("Replay or non-monotonic telemetry")
        dl = packet.encoder_left - old.encoder_left
        dr = packet.encoder_right - old.encoder_right
        max_ticks = self.calibration.maximum_ticks_per_sample
        if abs(dl) > max_ticks or abs(dr) > max_ticks:
            raise ValueError("Unrealistic encoder jump; explicit reset required")
        tick_distance = (2 * math.pi * self.calibration.wheel_radius_m
                         / self.calibration.ticks_per_revolution)
        left_m, right_m = dl * tick_distance, dr * tick_distance
        linear_m = (left_m + right_m) / 2
        delta_heading = (right_m - left_m) / self.calibration.wheel_base_m
        heading_mid = self.pose.heading_rad + delta_heading / 2
        next_pose = Pose2D(
            self.pose.x_m + linear_m * math.cos(heading_mid),
            self.pose.y_m + linear_m * math.sin(heading_mid),
            _normalize(self.pose.heading_rad + delta_heading),
        )
        if not all(math.isfinite(v) for v in (next_pose.x_m, next_pose.y_m, next_pose.heading_rad)):
            raise ValueError("Nonfinite odometry")
        self.pose = next_pose
        self.last_sample = packet
        return self.pose

    def reset(self, *, pose=Pose2D()):
        if not isinstance(pose, Pose2D) or not all(math.isfinite(v) for v in (pose.x_m, pose.y_m, pose.heading_rad)):
            raise ValueError("Invalid reset pose")
        self.pose = Pose2D(pose.x_m, pose.y_m, _normalize(pose.heading_rad))
        self.last_sample = None
