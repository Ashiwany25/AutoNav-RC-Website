
import unittest

from navigation.astar import astar
from navigation.safety_controller import (
    SafetyController,
    NavigationState,
)


class TestAStar(unittest.TestCase):

    def test_valid_route(self):
        grid = [
            [0, 0, 0],
            [0, 1, 0],
            [0, 0, 0],
        ]

        path = astar(grid, (0, 0), (2, 2))

        self.assertIsNotNone(path)
        self.assertEqual(path[0], (0, 0))
        self.assertEqual(path[-1], (2, 2))
        self.assertEqual(len(path) - 1, 4)

        for row, col in path:
            self.assertEqual(grid[row][col], 0)

    def test_blocked_destination(self):
        grid = [
            [0, 0, 0],
            [0, 1, 0],
            [0, 0, 0],
        ]

        path = astar(grid, (0, 0), (1, 1))
        self.assertIsNone(path)

    def test_unreachable_destination(self):
        grid = [
            [0, 1, 0],
            [0, 1, 0],
            [0, 1, 0],
        ]

        path = astar(grid, (0, 0), (0, 2))
        self.assertIsNone(path)

    def test_start_equals_goal(self):
        grid = [[0, 0], [0, 0]]
        path = astar(grid, (0, 0), (0, 0))
        self.assertEqual(path, [(0, 0)])

    def test_out_of_bounds_destination(self):
        grid = [[0, 0], [0, 0]]
        self.assertIsNone(
            astar(grid, (0, 0), (5, 5))
        )


class TestSafetyController(unittest.TestCase):

    def setUp(self):
        self.grid = [[0] * 9 for _ in range(9)]
        self.grid[4][4] = 1

        self.controller = SafetyController(
            self.grid, clearance=1
        )

    def test_obstacle_inflation(self):
        self.assertFalse(
            self.controller.is_safe((4, 4))
        )
        self.assertFalse(
            self.controller.is_safe((4, 3))
        )
        self.assertFalse(
            self.controller.is_safe((3, 3))
        )
        self.assertTrue(
            self.controller.is_safe((2, 2))
        )

    def test_unsafe_destination(self):
        path = self.controller.plan_route(
            (2, 2), (4, 4)
        )

        self.assertIsNone(path)
        self.assertEqual(
            self.controller.state,
            NavigationState.BLOCKED
        )

    def test_safe_route(self):
        path = self.controller.plan_route(
            (2, 2), (6, 6)
        )

        self.assertIsNotNone(path)
        self.assertEqual(
            self.controller.state,
            NavigationState.READY
        )

        for position in path:
            self.assertTrue(
                self.controller.is_safe(position)
            )

    def test_stop(self):
        self.controller.stop()

        self.assertEqual(
            self.controller.state,
            NavigationState.STOPPED
        )
        self.assertIsNone(self.controller.path)


class TestDynamicReplanning(unittest.TestCase):

    def test_route_changes_after_obstacle(self):
        grid = [[0] * 7 for _ in range(7)]

        controller = SafetyController(
            grid, clearance=0
        )

        start = (3, 1)
        goal = (3, 5)

        original_path = controller.plan_route(
            start, goal
        )

        self.assertIsNotNone(original_path)

        blocked = original_path[2]

        grid[blocked[0]][blocked[1]] = 1

        updated_controller = SafetyController(
            grid, clearance=0
        )

        new_path = updated_controller.plan_route(
            start, goal
        )

        self.assertIsNotNone(new_path)
        self.assertNotIn(blocked, new_path)
        self.assertNotEqual(original_path, new_path)


if __name__ == "__main__":
    unittest.main()
