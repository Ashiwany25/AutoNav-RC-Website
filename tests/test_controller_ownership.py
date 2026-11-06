import time
import unittest

from fastapi import HTTPException

from api.saved_map_simulator import SavedMapSimulator


class ControllerOwnershipTests(
    unittest.IsolatedAsyncioTestCase
):
    def make_simulator(self):
        sim = SavedMapSimulator(
            interval=0.5,
            heartbeat_timeout=3.0,
        )

        sim.state = "NAVIGATING"
        sim.owner_id = "phone-A"
        sim.position = (1, 1)
        sim.goal = (4, 4)
        sim.heartbeat_deadline = (
            time.monotonic() + 3
        )
        return sim

    async def test_owner_heartbeat_accepted(self):
        sim = self.make_simulator()

        result = await sim.heartbeat(
            controller_id="phone-A"
        )

        self.assertEqual(
            result["navigation_state"],
            "NAVIGATING",
        )

    async def test_other_controller_rejected(self):
        sim = self.make_simulator()

        with self.assertRaises(HTTPException) as caught:
            await sim.heartbeat(
                controller_id="phone-B"
            )

        self.assertEqual(
            caught.exception.status_code, 403
        )

    async def test_missing_identity_rejected(self):
        sim = self.make_simulator()

        with self.assertRaises(HTTPException):
            await sim.heartbeat(
                controller_id=None
            )

    async def test_wrong_owner_cannot_take_over(self):
        sim = self.make_simulator()

        with self.assertRaises(HTTPException) as caught:
            sim.require_owner_locked("phone-B")

        self.assertEqual(
            caught.exception.status_code, 403
        )

    async def test_status_does_not_change_owner(self):
        sim = self.make_simulator()

        await sim.status()

        self.assertEqual(
            sim.owner_id,
            "phone-A",
        )

    async def test_stop_remains_available(self):
        sim = self.make_simulator()

        await sim.stop()

        self.assertEqual(sim.state, "STOPPED")

    async def test_expired_heartbeat_cannot_resume(self):
        sim = self.make_simulator()
        sim.heartbeat_deadline = (
            time.monotonic() - 1
        )

        await sim.status()

        self.assertEqual(
            sim.state,
            "CONNECTION_LOST",
        )

        with self.assertRaises(HTTPException):
            await sim.heartbeat(
                controller_id="phone-A"
            )


if __name__ == "__main__":
    unittest.main()
