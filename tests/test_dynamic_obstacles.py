
import asyncio
import tempfile
import unittest
from pathlib import Path

from fastapi import HTTPException

from api.saved_map_simulator import SavedMapSimulator
from mapping.teach_mode import TeachModeMapper
from navigation.safety_controller import SafetyController


class TestDynamicObstacles(
    unittest.IsolatedAsyncioTestCase
):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.map_path = (
            Path(self.temp.name)
            / "dynamic_map.json"
        )

        mapper = TeachModeMapper(
            width=12,
            height=12,
            resolution=0.10,
        )

        mapper.grid = [
            [0] * 12
            for _ in range(12)
        ]

        mapper.update_robot_position(2, 2)
        mapper.save(self.map_path)

        self.sim = SavedMapSimulator(
            map_path=self.map_path,
            interval=0.03,
            heartbeat_timeout=3.0,
        )

    async def asyncTearDown(self):
        await self.sim.stop()
        self.temp.cleanup()

    async def test_obstacle_added(self):
        result = await self.sim.update_obstacle(
            5, 5, True
        )

        self.assertTrue(
            result["obstacle_changed"]
        )

        self.assertEqual(
            result["dynamic_obstacle_count"],
            1,
        )

        self.assertIn(
            {"row": 5, "col": 5},
            result["dynamic_obstacles"],
        )

    async def test_obstacle_removed(self):
        await self.sim.update_obstacle(
            5, 5, True
        )

        result = await self.sim.update_obstacle(
            5, 5, False
        )

        self.assertEqual(
            result["dynamic_obstacle_count"],
            0,
        )

    async def test_duplicate_observation(self):
        await self.sim.update_obstacle(
            5, 5, True
        )

        second = await self.sim.update_obstacle(
            5, 5, True
        )

        self.assertFalse(
            second["obstacle_changed"]
        )

        self.assertEqual(
            second["dynamic_obstacle_count"],
            1,
        )

    async def test_replans_around_obstacle(self):
        await self.sim.start((2, 9))

        result = await self.sim.update_obstacle(
            2, 5, True
        )

        self.assertTrue(
            result["replanned"]
        )

        self.assertEqual(
            result["navigation_state"],
            "NAVIGATING",
        )

        self.assertEqual(
            result["replan_count"],
            1,
        )

        mapper = TeachModeMapper.load(
            self.map_path
        )

        grid = self.sim.effective_grid(mapper)

        controller = SafetyController(
            grid,
            clearance=1,
        )

        for point in result["path"]:
            self.assertTrue(
                controller.is_safe(
                    (point["row"], point["col"])
                )
            )

        self.assertNotIn(
            {"row": 2, "col": 5},
            result["path"],
        )

    async def test_block_when_obstacle_too_close(self):
        await self.sim.start((2, 9))

        result = await self.sim.update_obstacle(
            2, 3, True
        )

        self.assertFalse(
            result["replanned"]
        )

        self.assertEqual(
            result["navigation_state"],
            "BLOCKED",
        )

        self.assertEqual(
            result["path"],
            [],
        )

    async def test_obstacle_outside_map(self):
        with self.assertRaises(
            HTTPException
        ) as context:
            await self.sim.update_obstacle(
                100, 100, True
            )

        self.assertEqual(
            context.exception.status_code,
            400,
        )

    async def test_unknown_cell_not_editable(self):
        mapper = TeachModeMapper.load(
            self.map_path
        )

        mapper.grid[9][9] = -1
        mapper.save(self.map_path)

        with self.assertRaises(
            HTTPException
        ) as context:
            await self.sim.update_obstacle(
                9, 9, True
            )

        self.assertEqual(
            context.exception.status_code,
            400,
        )

    async def test_dynamic_obstacle_preserves_saved_map(self):
        before = self.map_path.read_bytes()

        await self.sim.update_obstacle(
            5, 5, True
        )

        after = self.map_path.read_bytes()

        self.assertEqual(
            before,
            after,
        )

    async def test_stop_still_works(self):
        await self.sim.start((2, 9))

        await self.sim.update_obstacle(
            2, 5, True
        )

        stopped = await self.sim.stop()

        self.assertEqual(
            stopped["navigation_state"],
            "STOPPED",
        )

        position = stopped["position"]

        await asyncio.sleep(0.12)

        status = await self.sim.status()

        self.assertEqual(
            status["position"],
            position,
        )

    async def test_goal_blocked_by_obstacle(self):
        await self.sim.start((2, 9))

        result = await self.sim.update_obstacle(
            2, 9, True
        )

        self.assertEqual(
            result["navigation_state"],
            "BLOCKED",
        )

        self.assertEqual(
            result["path"],
            [],
        )


if __name__ == "__main__":
    unittest.main()
