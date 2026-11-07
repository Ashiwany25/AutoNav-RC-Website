import math
import unittest
from mapping.teach_mode import TeachModeMapper, UNKNOWN, FREE, OCCUPIED
from mapping.range_mapper import RangeGridMapper, RangeReading
from navigation.localized_planner import LocalizedPlanner, PoseEstimate
from hardware.wheel_odometry import Pose2D

class MappingTests(unittest.TestCase):
    def setUp(self):
        self.grid = TeachModeMapper(width=12, height=12, resolution=1)
        self.ray = RangeGridMapper(self.grid, max_range_m=7)
        self.pose = Pose2D(3.5, 3.5, 0)

    def test_hit_marks_wall_and_free_beam(self):
        self.ray.integrate(self.pose, [RangeReading(0, 3, True)])
        self.assertEqual(self.grid.grid[3][6], OCCUPIED)
        self.assertEqual(self.grid.grid[3][4], FREE)
        self.assertEqual(self.grid.robot_position, (3, 3))

    def test_no_hit_does_not_invent_wall(self):
        self.ray.integrate(self.pose, [RangeReading(0, 3, False)])
        self.assertEqual(self.grid.grid[3][6], FREE)

    def test_invalid_scan_is_transactional(self):
        with self.assertRaises(ValueError):
            self.ray.integrate(self.pose, [RangeReading(0, 2, True), RangeReading(0, 99, True)])
        self.assertTrue(all(c == UNKNOWN for row in self.grid.grid for c in row))

    def test_conflicting_free_does_not_erase_wall(self):
        self.ray.integrate(self.pose, [RangeReading(0, 3, True)])
        self.ray.integrate(self.pose, [RangeReading(0, 4, False)])
        self.assertEqual(self.grid.grid[3][6], OCCUPIED)

    def test_pose_outside_map_rejected(self):
        with self.assertRaises(ValueError):
            self.ray.integrate(Pose2D(-1, 0, 0), [RangeReading(0, 2, True)])

    def test_unknown_space_blocks_route(self):
        p = LocalizedPlanner(self.grid, clearance_cells=0)
        with self.assertRaises(ValueError):
            p.route(PoseEstimate(self.pose, 10.0, True), (3, 6), now=10.1)

    def test_complete_known_clear_map(self):
        for r in range(12):
            for c in range(12): self.grid.update_cell(r, c, FREE)
        p = LocalizedPlanner(self.grid, clearance_cells=1)
        path = p.route(PoseEstimate(self.pose, 10, True), (7, 7), now=10.1)
        self.assertEqual(path[0], (3, 3))
        self.assertEqual(path[-1], (7, 7))

    def test_untrusted_and_stale_pose_blocked(self):
        for r in range(12):
            for c in range(12): self.grid.update_cell(r, c, FREE)
        p = LocalizedPlanner(self.grid)
        for trust, stamp in [(False, 10), (True, 8)]:
            with self.assertRaises(ValueError):
                p.route(PoseEstimate(self.pose, stamp, trust), (7, 7), now=10)

    def test_obstacle_clearance(self):
        for r in range(12):
            for c in range(12): self.grid.update_cell(r, c, FREE)
        self.grid.update_cell(6, 6, OCCUPIED)
        p = LocalizedPlanner(self.grid, clearance_cells=1)
        with self.assertRaises(ValueError):
            p.route(PoseEstimate(self.pose, 10, True), (6, 7), now=10)
