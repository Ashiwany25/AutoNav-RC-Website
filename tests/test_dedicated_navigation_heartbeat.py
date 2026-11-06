import os
import time
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from api.saved_map_simulator import SavedMapSimulator


class DedicatedHeartbeatTests(
    unittest.IsolatedAsyncioTestCase
):
    def make_simulator(self):
        with patch.dict(
            os.environ,
            {"AUTONAV_DEDICATED_HEARTBEAT": "1"},
        ):
            simulator = SavedMapSimulator(
                interval=0.5,
                heartbeat_timeout=3.0,
            )

        simulator.state = "NAVIGATING"
        simulator.heartbeat_deadline = (
            time.monotonic() + 3.0
        )

        return simulator

    async def test_status_does_not_extend_lease(self):
        sim = self.make_simulator()
        original = sim.heartbeat_deadline

        await sim.status()

        self.assertEqual(
            sim.heartbeat_deadline,
            original,
        )

    async def test_heartbeat_renews_lease(self):
        sim = self.make_simulator()
        sim.heartbeat_deadline = (
            time.monotonic() + 0.5
        )

        old = sim.heartbeat_deadline
        await sim.heartbeat()

        self.assertGreater(
            sim.heartbeat_deadline,
            old,
        )

    async def test_expired_lease_cannot_be_revived(self):
        sim = self.make_simulator()
        sim.heartbeat_deadline = (
            time.monotonic() - 1.0
        )

        await sim.status()

        self.assertEqual(
            sim.state,
            "CONNECTION_LOST",
        )

        with self.assertRaises(HTTPException):
            await sim.heartbeat()

        self.assertEqual(
            sim.state,
            "CONNECTION_LOST",
        )

    async def test_stopped_navigation_cannot_heartbeat(self):
        sim = self.make_simulator()
        sim.state = "STOPPED"

        with self.assertRaises(HTTPException):
            await sim.heartbeat()


if __name__ == "__main__":
    unittest.main()
