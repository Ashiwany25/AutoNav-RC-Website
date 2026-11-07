
import tkinter as tk
from tkinter import messagebox

import httpx


API_URL = "http://127.0.0.1:8000/api/v1"
CELL_SIZE = 40
REFRESH_MS = 500

COLORS = {
    "free": "#E8EFF5",
    "occupied": "#526174",
    "robot": "#24946C",
    "goal": "#287BD5",
    "path": "#F0C35B",
}


class APIMapViewer:

    def __init__(self, root):
        self.root = root
        self.root.title("AutoNav RC - API Controlled Navigation")

        self.client = httpx.Client(
            base_url=API_URL,
            timeout=3.0
        )

        self.grid = []
        self.robot_position = None

        self.goal = None
        self.path = []

        self.navigation_state = "IDLE"
        self.job = None
        self.closed = False

        self.last_status = None
        self.local_goal_pending = False

        self.title_label = tk.Label(
            root,
            text="AutoNav RC - Autonomous Navigation",
            font=("Arial", 17, "bold")
        )
        self.title_label.pack(pady=8)

        self.status = tk.Label(
            root,
            text="Connecting to AutoNav API...",
            font=("Arial", 11)
        )
        self.status.pack(pady=5)

        self.position_label = tk.Label(
            root,
            text="Robot position: Unknown",
            font=("Arial", 11)
        )
        self.position_label.pack(pady=3)

        self.canvas = tk.Canvas(
            root,
            bg="white",
            highlightthickness=0
        )
        self.canvas.pack(padx=15, pady=10)

        self.canvas.bind(
            "<Button-1>",
            self.select_destination
        )

        controls = tk.Frame(root)
        controls.pack(pady=10)

        tk.Button(
            controls,
            text="Start Navigation",
            command=self.start_navigation
        ).pack(side="left", padx=4)

        tk.Button(
            controls,
            text="STOP",
            command=self.stop_navigation
        ).pack(side="left", padx=4)

        tk.Button(
            controls,
            text="Refresh Map",
            command=self.refresh_map
        ).pack(side="left", padx=4)

        self.root.protocol(
            "WM_DELETE_WINDOW",
            self.on_close
        )

        self.refresh_map()
        self.update_navigation()

    # ---------------- API METHODS ----------------

    def api_get(self, endpoint):
        response = self.client.get(endpoint)
        response.raise_for_status()
        return response.json()

    def api_post(self, endpoint, payload=None):
        response = self.client.post(
            endpoint,
            json=payload
        )
        response.raise_for_status()
        return response.json()

    # ---------------- MAP LOADING ----------------

    def refresh_map(self):
        try:
            data = self.api_get("/maps/current")

            grid = data["grid"]

            if not grid or not grid[0]:
                raise ValueError("Empty map received.")

            self.grid = grid

            position = data["robot_position"]

            self.robot_position = (
                position["row"],
                position["col"]
            )

            rows = len(self.grid)
            cols = len(self.grid[0])

            self.canvas.config(
                width=cols * CELL_SIZE,
                height=rows * CELL_SIZE
            )

            self.update_position_label()
            self.draw_map()

        except (
            httpx.HTTPError,
            KeyError,
            ValueError,
            IndexError
        ) as error:
            self.status.config(
                text=f"Map loading failed: {error}"
            )

    def update_position_label(self):
        self.position_label.config(
            text=f"Robot position: {self.robot_position}"
        )

    # ---------------- DESTINATION ----------------

    def select_destination(self, event):

        if not self.grid:
            return

        if self.navigation_state == "NAVIGATING":
            self.status.config(
                text="Press STOP before selecting a new destination."
            )
            return

        row = event.y // CELL_SIZE
        col = event.x // CELL_SIZE

        if not (
            0 <= row < len(self.grid)
            and 0 <= col < len(self.grid[0])
        ):
            return

        if self.grid[row][col] != 0:
            self.status.config(
                text="Rejected: destination is inside an obstacle."
            )
            return

        try:
            data = self.api_post(
                "/navigation/plan",
                {
                    "goal": {
                        "row": row,
                        "col": col
                    }
                }
            )

            self.goal = (row, col)

            self.path = [
                (cell["row"], cell["col"])
                for cell in data["path"]
            ]

            self.local_goal_pending = True
            self.navigation_state = "READY"

            self.status.config(
                text=(
                    f"READY | Goal: {self.goal} | "
                    f"Steps: {data['steps']}"
                )
            )

            self.draw_map()

        except httpx.HTTPStatusError as error:
            self.status.config(
                text=(
                    "Destination rejected: "
                    f"HTTP {error.response.status_code}"
                )
            )

        except httpx.HTTPError as error:
            self.status.config(
                text=f"API connection error: {error}"
            )

    # ---------------- START NAVIGATION ----------------

    def start_navigation(self):

        if self.goal is None:
            self.status.config(
                text="Select a destination first."
            )
            return

        if self.navigation_state == "NAVIGATING":
            self.status.config(
                text="Robot is already navigating."
            )
            return

        try:
            data = self.api_post(
                "/navigation/start",
                {
                    "goal": {
                        "row": self.goal[0],
                        "col": self.goal[1]
                    }
                }
            )

            self.navigation_state = data[
                "navigation_state"
            ]

            self.local_goal_pending = False

            self.status.config(
                text=f"State: {self.navigation_state}"
            )

        except httpx.HTTPStatusError as error:
            self.status.config(
                text=(
                    "Navigation request rejected: "
                    f"HTTP {error.response.status_code}"
                )
            )

        except httpx.HTTPError as error:
            self.status.config(
                text=f"Start failed: {error}"
            )

    # ---------------- STOP NAVIGATION ----------------

    def stop_navigation(self):

        try:
            data = self.api_post(
                "/navigation/stop"
            )

            self.navigation_state = data[
                "navigation_state"
            ]

            # Clear the previous destination and route.
            self.goal = None
            self.path = []

            self.local_goal_pending = False
            self.last_status = "STOPPED"

            # Get the latest robot position.
            self.refresh_map()

            self.status.config(
                text="STOPPED. Select a new destination."
            )

            self.draw_map()

        except httpx.HTTPError as error:
            self.status.config(
                text=f"STOP request failed: {error}"
            )

    # ---------------- LIVE UPDATES ----------------

    
    def update_navigation(self):
        """
        Synchronize robot position, map, and navigation
        state with AutoNav API v1.

        Automatically retries after connection failures.
        """

        self.job = None

        if self.closed:
            return

        try:
            # Get current robot status from AutoNav API.
            data = self.api_get("/navigation/status")

            server_state = data["navigation_state"]
            position = data["position"]

            self.robot_position = (
                position["row"],
                position["col"]
            )

            # Preserve any new goal selected locally.
            if not self.local_goal_pending:

                self.navigation_state = server_state

                if server_state == "NAVIGATING":

                    server_goal = data.get("goal")

                    if server_goal is not None:
                        self.goal = (
                            server_goal["row"],
                            server_goal["col"]
                        )

                    # Remove route cells already visited.
                    if self.robot_position in self.path:
                        index = self.path.index(
                            self.robot_position
                        )

                        self.path = self.path[index:]

                    self.status.config(
                        text=(
                            "NAVIGATING | "
                            f"Step {data['current_step']}/"
                            f"{data['total_steps']} | "
                            f"Remaining: {data['remaining_steps']}"
                        ),
                        fg="green"
                    )

                elif server_state == "ARRIVED":

                    self.path = []

                    self.status.config(
                        text="ARRIVED: Destination reached!",
                        fg="green"
                    )

                elif server_state == "STOPPED":

                    self.path = []
                    self.goal = None

                    self.status.config(
                        text="STOPPED: Select a new destination.",
                        fg="red"
                    )

                elif server_state == "BLOCKED":

                    self.path = []

                    self.status.config(
                        text="BLOCKED: No safe route available.",
                        fg="red"
                    )

                elif server_state == "IDLE":

                    self.status.config(
                        text="IDLE: Select a destination.",
                        fg="black"
                    )

            # Automatically refresh the map every
            # fourth update (approximately 2 seconds).
            self.map_refresh_counter = (
                getattr(self, "map_refresh_counter", 0) + 1
            )

            if self.map_refresh_counter >= 4:

                self.map_refresh_counter = 0

                try:
                    map_data = self.api_get("/maps/current")

                    self.grid = map_data["grid"]

                    rows = len(self.grid)
                    cols = len(self.grid[0])

                    self.canvas.config(
                        width=cols * CELL_SIZE,
                        height=rows * CELL_SIZE
                    )

                except (
                    httpx.HTTPError,
                    KeyError,
                    ValueError
                ):
                    # Keep displaying the last valid map.
                    pass

            self.update_position_label()
            self.draw_map()

        except (
            httpx.HTTPError,
            KeyError,
            ValueError
        ) as error:

            self.status.config(
                text=(
                    "DISCONNECTED: Waiting for AutoNav API..."
                ),
                fg="red"
            )

            print("AutoNav API connection error:", error)

        finally:

            # Continue polling even if a connection fails.
            if not self.closed:
                self.job = self.root.after(
                    REFRESH_MS,
                    self.update_navigation
                )

    # ---------------- MAP DRAWING ----------------

    def draw_map(self):

        self.canvas.delete("all")

        path_cells = set(self.path)

        for r, row in enumerate(self.grid):
            for c, cell in enumerate(row):

                position = (r, c)

                if position == self.robot_position:
                    color = COLORS["robot"]

                elif position == self.goal:
                    color = COLORS["goal"]

                elif cell == 1:
                    color = COLORS["occupied"]

                elif position in path_cells:
                    color = COLORS["path"]

                else:
                    color = COLORS["free"]

                x = c * CELL_SIZE
                y = r * CELL_SIZE

                self.canvas.create_rectangle(
                    x,
                    y,
                    x + CELL_SIZE,
                    y + CELL_SIZE,
                    fill=color,
                    outline="white",
                    width=1
                )

                if position == self.robot_position:
                    label = "R"

                elif position == self.goal:
                    label = "G"

                else:
                    label = None

                if label:
                    self.canvas.create_text(
                        x + CELL_SIZE / 2,
                        y + CELL_SIZE / 2,
                        text=label,
                        fill="white",
                        font=("Arial", 13, "bold")
                    )

    # ---------------- CLOSE APPLICATION ----------------

    def on_close(self):

        self.closed = True

        if self.job is not None:
            self.root.after_cancel(self.job)
            self.job = None

        # Best-effort stop if the viewer closes
        # while simulated navigation is active.
        if self.navigation_state == "NAVIGATING":
            try:
                self.api_post("/navigation/stop")
            except httpx.HTTPError:
                pass

        self.client.close()
        self.root.destroy()


def main():
    root = tk.Tk()
    APIMapViewer(root)
    root.mainloop()


if __name__ == "__main__":
    main()
