
import asyncio
import tempfile
import unittest

from pathlib import Path

from api.saved_map_simulator import SavedMapSimulator
from mapping.teach_mode import TeachModeMapper


class TestSavedMapWatchdog(
    unittest.IsolatedAsyncioTestCase
):
    async def asyncSetUp(self):
        self.temporary = tempfile.TemporaryDirectory()

        self.map_path = (
            Path(self.temporary.name)
            / "watchdog_map.json"
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

        self.simulator = SavedMapSimulator(
            map_path=self.map_path,
            interval=0.03,
            heartbeat_timeout=0.16,
        )

    async def asyncTearDown(self):
        await self.simulator.stop()
        self.temporary.cleanup()

    async def test_disconnect_stops_movement(self):
        await self.simulator.start((9, 9))

        await asyncio.sleep(0.28)

        status = await self.simulator.status()

        self.assertEqual(
            status["navigation_state"],
            "CONNECTION_LOST",
        )

        self.assertTrue(
            status["communication_lost"]
        )

        self.assertEqual(
            status["path"],
            [],
        )

        position = status["position"]

        await asyncio.sleep(0.12)

        after = await self.simulator.status()

        self.assertEqual(
            after["position"],
            position,
        )

    async def test_status_polling_keeps_simulation_alive(self):
        await self.simulator.start((9, 9))

        for _ in range(6):
            await asyncio.sleep(0.04)

            status = await self.simulator.status()

            self.assertEqual(
                status["navigation_state"],
                "NAVIGATING",
            )

            self.assertGreater(
                status["heartbeat_remaining_ms"],
                0,
            )

    async def test_reconnection_does_not_restart(self):
        await self.simulator.start((9, 9))

        await asyncio.sleep(0.28)

        first = await self.simulator.status()
        second = await self.simulator.status()

        self.assertEqual(
            first["navigation_state"],
            "CONNECTION_LOST",
        )

        self.assertEqual(
            second["navigation_state"],
            "CONNECTION_LOST",
        )

        self.assertEqual(
            first["position"],
            second["position"],
        )

    async def test_new_start_can_resume_after_timeout(self):
        await self.simulator.start((9, 9))

        await asyncio.sleep(0.28)

        expired = await self.simulator.status()

        self.assertEqual(
            expired["navigation_state"],
            "CONNECTION_LOST",
        )

        restarted = await self.simulator.start((9, 9))

        self.assertEqual(
            restarted["navigation_state"],
            "NAVIGATING",
        )

        self.assertFalse(
            restarted["communication_lost"]
        )

    async def test_stop_remains_stopped(self):
        await self.simulator.start((9, 9))

        await asyncio.sleep(0.05)

        stopped = await self.simulator.stop()

        self.assertEqual(
            stopped["navigation_state"],
            "STOPPED",
        )

        await asyncio.sleep(0.25)

        after = await self.simulator.status()

        self.assertEqual(
            after["navigation_state"],
            "STOPPED",
        )


if __name__ == "__main__":
    unittest.main()
