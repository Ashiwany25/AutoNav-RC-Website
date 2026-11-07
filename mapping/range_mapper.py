"""Conservative 2D occupancy updates from a calibrated planar range sensor.

Sensor values are simulated/offline until installed and calibrated on hardware.
Grid: -1 unknown, 0 free, 1 occupied. Existing occupied cells are never
cleared by one observation; map conflict requires a separate fusion policy.
No motor commands are emitted.
"""
from dataclasses import dataclass
import math
from mapping.teach_mode import TeachModeMapper, UNKNOWN, FREE, OCCUPIED
from hardware.wheel_odometry import Pose2D


@dataclass(frozen=True)
class RangeReading:
    angle_rad: float  # relative to robot +x, counterclockwise
    distance_m: float
    hit: bool  # False if maximum-range return with no obstacle

    def __post_init__(self):
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in (self.angle_rad, self.distance_m)):
            raise ValueError('Nonfinite range reading')
        if type(self.hit) is not bool:
            raise ValueError('hit must be bool')


class RangeGridMapper:
    """Map world x right / y down to grid row and column; cell centers at n+0.5."""
    def __init__(self, grid: TeachModeMapper, *, max_range_m=4.0, minimum_range_m=0.03):
        if not isinstance(grid, TeachModeMapper):
            raise TypeError('Expected TeachModeMapper')
        if not (math.isfinite(max_range_m) and math.isfinite(minimum_range_m) and
                0 < minimum_range_m < max_range_m):
            raise ValueError('Invalid range limits')
        self.grid = grid
        self.max_range_m = max_range_m
        self.minimum_range_m = minimum_range_m

    def cell(self, x, y):
        if not (math.isfinite(x) and math.isfinite(y)):
            raise ValueError('Nonfinite world coordinates')
        return math.floor(y / self.grid.resolution), math.floor(x / self.grid.resolution)

    def integrate(self, pose: Pose2D, readings: list[RangeReading]):
        """Transactional: rejects whole scan before mutation if invalid/out of map.

        Sensor beam must start inside map. Rays leaving the bounded map
        terminate at its edge. Hit endpoint outside map is not marked occupied.
        """
        if not isinstance(pose, Pose2D) or not all(math.isfinite(v) for v in (pose.x_m, pose.y_m, pose.heading_rad)):
            raise ValueError('Invalid pose')
        if not isinstance(readings, (list, tuple)) or not 0 < len(readings) <= 720:
            raise ValueError('Invalid scan length')
        origin = self.cell(pose.x_m, pose.y_m)
        if not self.grid.in_bounds(*origin):
            raise ValueError('Robot outside map')
        updates = {}
        for ray in readings:
            if not isinstance(ray, RangeReading) or not self.minimum_range_m <= ray.distance_m <= self.max_range_m:
                raise ValueError('Range sample outside sensor bounds')
            theta = pose.heading_rad + ray.angle_rad
            step = self.grid.resolution / 4
            # Deduplicate visited cells by sampling from origin to return location.
            visited = []
            n = max(1, math.ceil(ray.distance_m / step))
            for i in range(n + 1):
                d = ray.distance_m * i / n
                loc = self.cell(pose.x_m + d * math.cos(theta), pose.y_m + d * math.sin(theta))
                if not self.grid.in_bounds(*loc):
                    break
                if not visited or loc != visited[-1]:
                    visited.append(loc)
            if not visited:
                continue
            endpoint = self.cell(pose.x_m + ray.distance_m * math.cos(theta),
                                 pose.y_m + ray.distance_m * math.sin(theta))
            endpoint_in_map = self.grid.in_bounds(*endpoint)
            for cell in visited:
                value = OCCUPIED if ray.hit and endpoint_in_map and cell == endpoint else FREE
                # Occupied always wins over free in this scan.
                if value == OCCUPIED or updates.get(cell) != OCCUPIED:
                    updates[cell] = value
        for cell, value in updates.items():
            if self.grid.grid[cell[0]][cell[1]] == OCCUPIED and value == FREE:
                continue
            self.grid.update_cell(*cell, value)
        self.grid.update_robot_position(*origin)
        return len(updates)
