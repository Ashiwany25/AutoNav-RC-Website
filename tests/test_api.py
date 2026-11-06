
import unittest

from fastapi.testclient import TestClient
from api.main import app


class TestAutoNavAPI(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.client_context = TestClient(app)
        cls.client = cls.client_context.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls.client_context.__exit__(None, None, None)

    def test_health(self):
        response = self.client.get("/api/v1/health")

        self.assertEqual(response.status_code, 200)

        data = response.json()

        self.assertTrue(data["success"])
        self.assertTrue(data["simulation"])
        self.assertEqual(data["version"], "1.0.0")

    def test_robot_status(self):
        response = self.client.get(
            "/api/v1/robot/status"
        )

        self.assertEqual(response.status_code, 200)

        data = response.json()

        self.assertEqual(
            data["device_id"],
            "AUTONAV-SIM-001"
        )
        self.assertEqual(
            data["position"],
            {"row": 2, "col": 2}
        )
        self.assertTrue(data["simulation"])

    def test_valid_navigation_request(self):
        response = self.client.post(
            "/api/v1/navigation/plan",
            json={
                "goal": {
                    "row": 12,
                    "col": 12
                }
            }
        )

        self.assertEqual(response.status_code, 200)

        data = response.json()

        self.assertTrue(data["success"])
        self.assertEqual(
            data["goal"],
            {"row": 12, "col": 12}
        )
        self.assertGreater(data["steps"], 0)
        self.assertEqual(
            data["navigation_state"],
            "READY"
        )

    def test_unsafe_destination(self):
        response = self.client.post(
            "/api/v1/navigation/plan",
            json={
                "goal": {
                    "row": 5,
                    "col": 6
                }
            }
        )

        self.assertEqual(response.status_code, 400)

    def test_outside_map(self):
        response = self.client.post(
            "/api/v1/navigation/plan",
            json={
                "goal": {
                    "row": 100,
                    "col": 100
                }
            }
        )

        self.assertEqual(response.status_code, 400)

    def test_invalid_negative_position(self):
        response = self.client.post(
            "/api/v1/navigation/plan",
            json={
                "goal": {
                    "row": -1,
                    "col": 5
                }
            }
        )

        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
