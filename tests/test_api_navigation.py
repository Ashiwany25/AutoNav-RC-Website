
import time
import unittest

from fastapi.testclient import TestClient

from api.main import app, robot
from navigation.safety_controller import SafetyController


class TestAPINavigation(unittest.TestCase):

    def setUp(self):
        self.client_context = TestClient(app)
        self.client = self.client_context.__enter__()

        # Ensure no previous simulated navigation remains active.
        self.client.post("/api/v1/navigation/stop")

        # Restore the shared test robot to a known state.
        robot.position = (2, 2)
        robot.goal = None
        robot.path = []
        robot.mode = "IDLE"
        robot.current_step = 0
        robot.total_steps = 0
        robot.task = None
        robot.controller = SafetyController(
            robot.grid, clearance=1
        )

    def tearDown(self):
        self.client.post("/api/v1/navigation/stop")
        self.client_context.__exit__(None, None, None)

    def test_navigation_start(self):
        response = self.client.post(
            "/api/v1/navigation/start",
            json={"goal": {"row": 12, "col": 12}}
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["success"])
        self.assertEqual(
            response.json()["navigation_state"],
            "NAVIGATING"
        )

    def test_navigation_status(self):
        response = self.client.get(
            "/api/v1/navigation/status"
        )

        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIn("navigation_state", data)
        self.assertIn("position", data)
        self.assertIn("current_step", data)

    def test_invalid_goal(self):
        response = self.client.post(
            "/api/v1/navigation/start",
            json={"goal": {"row": 5, "col": 6}}
        )

        self.assertEqual(response.status_code, 400)

    def test_stop(self):
        self.client.post(
            "/api/v1/navigation/start",
            json={"goal": {"row": 12, "col": 12}}
        )

        response = self.client.post(
            "/api/v1/navigation/stop"
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["navigation_state"],
            "STOPPED"
        )

        first_position = self.client.get(
            "/api/v1/navigation/status"
        ).json()["position"]

        time.sleep(0.7)

        second_position = self.client.get(
            "/api/v1/navigation/status"
        ).json()["position"]

        self.assertEqual(first_position, second_position)

    def test_already_at_destination(self):
        response = self.client.post(
            "/api/v1/navigation/start",
            json={"goal": {"row": 2, "col": 2}}
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["navigation_state"],
            "ARRIVED"
        )


if __name__ == "__main__":
    unittest.main()
