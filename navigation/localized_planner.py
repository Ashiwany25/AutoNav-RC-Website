"""Fail-closed offline bridge between metric localization and existing A* map planner.

No automatic movement: returns a route proposal only. Localization confidence
is external and must be explicitly marked valid by the sensor pipeline.
"""
from dataclasses import dataclass
from math import floor, isfinite
from hardware.wheel_odometry import Pose2D
from mapping.teach_mode import TeachModeMapper
from navigation.safety_controller import SafetyController


@dataclass(frozen=True)
class PoseEstimate:
    pose: Pose2D
    timestamp: float
    trustworthy: bool


class LocalizedPlanner:
    def __init__(self, mapper: TeachModeMapper, *, clearance_cells=1, max_age_s=0.5):
        if not isinstance(mapper, TeachModeMapper):
            raise TypeError('Invalid map')
        if type(clearance_cells) is not int or clearance_cells < 0:
            raise ValueError('Invalid clearance')
        if not isfinite(max_age_s) or max_age_s <= 0:
            raise ValueError('Invalid estimate age')
        self.mapper = mapper
        self.clearance_cells = clearance_cells
        self.max_age_s = max_age_s

    def route(self, estimate: PoseEstimate, goal, *, now):
        if not isinstance(estimate, PoseEstimate) or not isinstance(estimate.pose, Pose2D):
            raise ValueError('Missing pose estimate')
        if not (estimate.trustworthy and isfinite(now) and isfinite(estimate.timestamp)
                and 0 <= now - estimate.timestamp <= self.max_age_s):
            raise ValueError('Localization unavailable or stale: STOP required')
        pose = estimate.pose
        if not all(isfinite(v) for v in (pose.x_m, pose.y_m, pose.heading_rad)):
            raise ValueError('Invalid pose')
        if not (isinstance(goal, tuple) and len(goal) == 2 and all(type(v) is int for v in goal)):
            raise ValueError('Invalid goal')
        start = (floor(pose.y_m / self.mapper.resolution), floor(pose.x_m / self.mapper.resolution))
        controller = SafetyController(self.mapper.grid, clearance=self.clearance_cells)
        if not controller.is_safe(start) or not controller.is_safe(goal):
            raise ValueError('Unsafe start or goal')
        path = controller.plan_route(start, goal)
        if path is None:
            raise ValueError('No safe route')
        return path
