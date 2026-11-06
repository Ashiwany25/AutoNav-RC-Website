import os
import time
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from api.saved_map_simulator import SavedMapSimulator


class ShortRouteWatchdogTests(
    unittest.IsolatedAsyncioTestCase
):
    def make_simulator(self):
        with patch.dict(
            os.environ,
            {"AUTONAV_DEDICATED_HEARTBEAT": "1"},
        ):
            sim = SavedMapSimulator(
                interval=0.5,
                heartbeat_timeout=3.0,
            )

        return sim

    async def test_dedicated_timeout_is_shorter(self):
        sim = self.make_simulator()
        self.assertEqual(
            sim.heartbeat_timeout, 1.5
        )

    async def test_status_does_not_renew_lease(self):
        sim = self.make_simulator()
        sim.state = "NAVIGATING"

        deadline = time.monotonic() + 1.5
        sim.heartbeat_deadline = deadline

        await sim.status()

        self.assertEqual(
            sim.heartbeat_deadline,
            deadline,
        )

    async def test_connection_loss_stops_movement(self):
        sim = self.make_simulator()
        sim.state = "NAVIGATING"
        sim.position = (1, 2)
        sim.goal = (4, 4)
        sim.path = [
            (1, 2),
            (1, 3),
            (1, 4),
            (2, 4),
            (3, 4),
            (4, 4),
        ]

        old_position = sim.position
        sim.heartbeat_deadline = (
            time.monotonic() - 0.1
        )

        await sim.status()

        self.assertEqual(
            sim.state,
            "CONNECTION_LOST",
        )
        self.assertEqual(sim.position, old_position)
        self.assertEqual(sim.path, [])

        with self.assertRaises(HTTPException):
            await sim.heartbeat()

        self.assertEqual(
            sim.position,
            old_position,
        )

    async def test_explicit_stop_is_terminal(self):
        sim = self.make_simulator()
        sim.state = "NAVIGATING"
        sim.position = (1, 2)
        sim.goal = (4, 4)

        await sim.stop()

        self.assertEqual(sim.state, "STOPPED")
        self.assertIsNone(sim.goal)
        self.assertEqual(sim.path, [])


if __name__ == "__main__":
    unittest.main()
