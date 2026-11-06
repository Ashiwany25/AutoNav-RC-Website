import os
import time
import unittest
from unittest.mock import patch

from fastapi import HTTPException
from api.saved_map_simulator import SavedMapSimulator


class IndependentHeartbeatSafetyTests(
    unittest.IsolatedAsyncioTestCase
):
    def create_simulator(self):
        with patch.dict(
            os.environ,
            {"AUTONAV_DEDICATED_HEARTBEAT": "1"},
        ):
            sim = SavedMapSimulator(
                interval=0.5,
                heartbeat_timeout=3.0,
            )

        sim.state = "NAVIGATING"
        sim.position = (1, 1)
        sim.goal = (4, 4)
        sim.path = [
            (1, 1),
            (1, 2),
            (1, 3),
            (2, 3),
            (3, 3),
            (4, 3),
            (4, 4),
        ]

        sim.renew_heartbeat_locked()
        return sim

    async def test_status_cannot_extend_heartbeat(self):
        sim = self.create_simulator()
        deadline = sim.heartbeat_deadline

        for _ in range(10):
            await sim.status()

        self.assertEqual(
            sim.heartbeat_deadline,
            deadline,
        )

    async def test_missing_heartbeat_stops_robot(self):
        sim = self.create_simulator()
        initial_position = sim.position

        sim.heartbeat_deadline = (
            time.monotonic() - 1
        )

        result = await sim.status()

        self.assertEqual(
            result["navigation_state"],
            "CONNECTION_LOST",
        )

        self.assertEqual(
            sim.position,
            initial_position,
        )

        self.assertEqual(sim.path, [])

    async def test_late_heartbeat_cannot_restart(self):
        sim = self.create_simulator()
        sim.heartbeat_deadline = (
            time.monotonic() - 1
        )

        await sim.status()

        with self.assertRaises(HTTPException):
            await sim.heartbeat()

        self.assertEqual(
            sim.state,
            "CONNECTION_LOST",
        )

    async def test_valid_heartbeat_extends_lease(self):
        sim = self.create_simulator()
        previous_deadline = sim.heartbeat_deadline

        await sim.heartbeat()

        self.assertGreaterEqual(
            sim.heartbeat_deadline,
            previous_deadline,
        )

    async def test_stop_prevents_restart(self):
        sim = self.create_simulator()

        await sim.stop()

        self.assertEqual(
            sim.state,
            "STOPPED",
        )

        with self.assertRaises(HTTPException):
            await sim.heartbeat()

        self.assertEqual(
            sim.state,
            "STOPPED",
        )


if __name__ == "__main__":
    unittest.main()
