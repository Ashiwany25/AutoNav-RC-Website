
import unittest
from unittest.mock import MagicMock, patch

import tkinter as tk
import httpx

from simulation.api_map_viewer import APIMapViewer


class TestMapViewer(unittest.TestCase):

    def setUp(self):
        self.root = tk.Tk()
        self.root.withdraw()

        self.map_data = {
            "success": True,
            "simulation": True,
            "map_name": "Test Map",
            "width": 5,
            "height": 5,
            "grid": [[0] * 5 for _ in range(5)],
            "robot_position": {
                "row": 1,
                "col": 1
            },
        }

        self.status_data = {
            "success": True,
            "simulation": True,
            "navigation_state": "IDLE",
            "position": {
                "row": 1,
                "col": 1
            },
            "goal": None,
            "current_step": 0,
            "total_steps": 0,
            "remaining_steps": 0,
        }

        # Prevent real HTTP requests during viewer initialization.
        self.get_patcher = patch.object(
            APIMapViewer,
            "api_get",
            side_effect=self.mock_api_get
        )
        self.mock_get = self.get_patcher.start()

        self.viewer = APIMapViewer(self.root)

        # Cancel scheduled polling to make tests deterministic.
        if self.viewer.job is not None:
            self.root.after_cancel(self.viewer.job)
            self.viewer.job = None

    def tearDown(self):
        self.viewer.closed = True

        if self.viewer.job is not None:
            self.root.after_cancel(self.viewer.job)
            self.viewer.job = None

        self.viewer.client.close()
        self.root.destroy()
        self.get_patcher.stop()

    def mock_api_get(self, endpoint):
        if endpoint == "/maps/current":
            return self.map_data

        if endpoint == "/navigation/status":
            return self.status_data

        raise ValueError(f"Unexpected endpoint: {endpoint}")

    def test_map_loading(self):
        self.assertEqual(len(self.viewer.grid), 5)
        self.assertEqual(len(self.viewer.grid[0]), 5)

    def test_robot_position(self):
        self.assertEqual(
            self.viewer.robot_position,
            (1, 1)
        )

    def test_navigation_status_update(self):
        self.status_data["navigation_state"] = "NAVIGATING"
        self.status_data["position"] = {
            "row": 2,
            "col": 2
        }
        self.status_data["goal"] = {
            "row": 4,
            "col": 4
        }

        self.viewer.update_navigation()

        self.assertEqual(
            self.viewer.robot_position,
            (2, 2)
        )

        self.assertEqual(
            self.viewer.navigation_state,
            "NAVIGATING"
        )

    def test_arrival_clears_route(self):
        self.viewer.path = [
            (1, 1),
            (2, 1),
            (3, 1)
        ]

        self.status_data["navigation_state"] = "ARRIVED"

        self.viewer.update_navigation()

        self.assertEqual(self.viewer.path, [])

    def test_stop_clears_route(self):
        self.viewer.path = [(1, 1), (2, 1)]
        self.viewer.goal = (4, 4)

        self.status_data["navigation_state"] = "STOPPED"

        self.viewer.update_navigation()

        self.assertEqual(self.viewer.path, [])
        self.assertIsNone(self.viewer.goal)

    def test_connection_error_and_recovery(self):
        original = self.viewer.api_get

        self.viewer.api_get = MagicMock(
            side_effect=httpx.ConnectError(
                "Simulated API disconnection"
            )
        )

        self.viewer.update_navigation()

        self.assertIn(
            "DISCONNECTED",
            self.viewer.status.cget("text")
        )

        # Restore the simulated API response.
        self.viewer.api_get = original

        self.viewer.update_navigation()

        self.assertEqual(
            self.viewer.robot_position,
            (1, 1)
        )

        self.assertNotIn(
            "DISCONNECTED",
            self.viewer.status.cget("text")
        )


if __name__ == "__main__":
    unittest.main()

