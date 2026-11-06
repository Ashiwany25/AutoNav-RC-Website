
import asyncio
import tempfile
import unittest

from pathlib import Path

from fastapi import HTTPException

from api.saved_map_simulator import SavedMapSimulator
from mapping.teach_mode import TeachModeMapper


class TestSavedMapSafety(
    unittest.IsolatedAsyncioTestCase
):
    async def asyncSetUp(self):
        self.temporary = tempfile.TemporaryDirectory()

        self.map_path = (
            Path(self.temporary.name)
            / "safety_test_map.json"
        )

        self.mapper = TeachModeMapper(
            width=12,
            height=12,
            resolution=0.10,
        )

        self.mapper.grid = [
            [0 for _ in range(12)]
            for _ in range(12)
        ]

        self.mapper.update_robot_position(2, 2)
        self.mapper.save(self.map_path)

        self.simulator = SavedMapSimulator(
            map_path=self.map_path,
            interval=0.03,
        )

    async def asyncTearDown(self):
        await self.simulator.stop()
        self.temporary.cleanup()

    async def wait_for_state(
        self,
        expected,
        timeout=2.0,
    ):
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout

        while loop.time() < deadline:
            status = await self.simulator.status()

            if status["navigation_state"] == expected:
                return status

            await asyncio.sleep(0.01)

        self.fail(
            f"Simulator did not reach {expected}. "
            f"Last status: {await self.simulator.status()}"
        )

    async def wait_for_progress(
        self,
        minimum=1,
        timeout=2.0,
    ):
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout

        while loop.time() < deadline:
            status = await self.simulator.status()

            if status["current_step"] >= minimum:
                return status

            await asyncio.sleep(0.01)

        self.fail(
            "Virtual robot did not make progress. "
            f"Last status: {await self.simulator.status()}"
        )

    async def test_start_navigation(self):
        status = await self.simulator.start((2, 9))

        self.assertEqual(
            status["navigation_state"],
            "NAVIGATING",
        )

        self.assertEqual(
            status["position"],
            {"row": 2, "col": 2},
        )

        self.assertEqual(
            status["goal"],
            {"row": 2, "col": 9},
        )

        self.assertFalse(
            status["physical_motors_active"]
        )

    async def test_stop_during_movement(self):
        await self.simulator.start((2, 9))

        await self.wait_for_progress()

        stopped = await self.simulator.stop()

        self.assertEqual(
            stopped["navigation_state"],
            "STOPPED",
        )

        self.assertEqual(stopped["path"], [])

        stopped_position = stopped["position"]

        await asyncio.sleep(0.12)

        after = await self.simulator.status()

        self.assertEqual(
            after["navigation_state"],
            "STOPPED",
        )

        self.assertEqual(
            after["position"],
            stopped_position,
        )

    async def test_destination_change(self):
        await self.simulator.start((2, 9))

        before = await self.wait_for_progress()

        old_position = before["position"]

        updated = await self.simulator.start(
            (9, 9)
        )

        self.assertEqual(
            updated["navigation_state"],
            "NAVIGATING",
        )

        self.assertEqual(
            updated["position"],
            old_position,
        )

        self.assertEqual(
            updated["goal"],
            {"row": 9, "col": 9},
        )

        self.assertEqual(
            updated["path"][0],
            old_position,
        )

        arrived = await self.wait_for_state(
            "ARRIVED"
        )

        self.assertEqual(
            arrived["position"],
            {"row": 9, "col": 9},
        )

    async def test_map_change_blocks_navigation(self):
        await self.simulator.start((2, 9))

        await self.wait_for_progress()

        changed = TeachModeMapper.load(
            self.map_path
        )

        changed.update_cell(
            10,
            10,
            1,
        )

        changed.save(self.map_path)

        blocked = await self.wait_for_state(
            "BLOCKED"
        )

        self.assertEqual(
            blocked["path"],
            [],
        )

        self.assertNotEqual(
            blocked["position"],
            {"row": 2, "col": 9},
        )

    async def test_unknown_goal_rejected(self):
        self.mapper.grid[9][9] = -1

        self.mapper.save(self.map_path)

        with self.assertRaises(
            HTTPException
        ) as context:
            await self.simulator.start(
                (9, 9)
            )

        self.assertEqual(
            context.exception.status_code,
            400,
        )

    async def test_obstacle_clearance_preserved(self):
        self.mapper.update_cell(
            9,
            9,
            1,
        )

        self.mapper.save(self.map_path)

        with self.assertRaises(
            HTTPException
        ) as context:
            await self.simulator.start(
                (8, 8)
            )

        self.assertEqual(
            context.exception.status_code,
            400,
        )

    async def test_status_recovery(self):
        await self.simulator.start(
            (2, 9)
        )

        await self.wait_for_progress()

        first = await self.simulator.status()

        second = await self.simulator.status()

        self.assertTrue(
            first["success"]
        )

        self.assertEqual(
            second["goal"],
            first["goal"],
        )

        self.assertEqual(
            second["navigation_state"],
            "NAVIGATING",
        )

        self.assertFalse(
            second["physical_motors_active"]
        )

    async def test_stop_is_idempotent(self):
        first = await self.simulator.stop()
        second = await self.simulator.stop()

        self.assertEqual(
            first["navigation_state"],
            "STOPPED",
        )

        self.assertEqual(
            second["navigation_state"],
            "STOPPED",
        )

    async def test_corrupted_map_rejected(self):
        self.map_path.write_text(
            '{"invalid":',
            encoding="utf-8",
        )

        with self.assertRaises(
            HTTPException
        ) as context:
            await self.simulator.start(
                (5, 5)
            )

        self.assertEqual(
            context.exception.status_code,
            500,
        )

    async def test_saved_map_not_overwritten(self):
        before = self.map_path.read_bytes()

        await self.simulator.start(
            (2, 9)
        )

        await self.wait_for_progress()

        await self.simulator.stop()

        after = self.map_path.read_bytes()

        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
