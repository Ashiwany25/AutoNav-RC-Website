
import sys
import tkinter as tk
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.safety_controller import (
    SafetyController,
    NavigationState,
)

CELL_SIZE = 42

COLORS = {
    "free": "#E8EFF5",
    "wall": "#526174",
    "clearance": "#E8B7B3",
    "path": "#F0C35B",
    "robot": "#24946C",
    "goal": "#287BD5",
    "new_obstacle": "#D94F4F",
}


def create_test_map():
    rows, cols = 15, 15
    grid = [[0] * cols for _ in range(rows)]

    for r in range(4, 11):
        grid[r][6] = 1

    for c in range(9, 13):
        grid[9][c] = 1

    return grid


class AutoNavSimulator:
    def __init__(self, root):
        self.root = root
        self.root.title(
            "AutoNav RC - Dynamic Obstacle Navigation"
        )

        self.original_grid = create_test_map()
        self.grid = [row.copy() for row in self.original_grid]

        self.controller = SafetyController(
            self.grid, clearance=1
        )

        self.robot = (2, 2)
        self.goal = None
        self.path = []
        self.running = False
        self.job = None
        self.new_obstacles = set()

        rows = len(self.grid)
        cols = len(self.grid[0])

        self.canvas = tk.Canvas(
            root,
            width=cols * CELL_SIZE,
            height=rows * CELL_SIZE,
            bg="white"
        )
        self.canvas.pack(padx=12, pady=12)

        self.canvas.bind(
            "<Button-1>", self.select_goal
        )

        self.status = tk.Label(
            root,
            text="Select a safe destination.",
            font=("Arial", 12)
        )
        self.status.pack(pady=5)

        controls = tk.Frame(root)
        controls.pack(pady=10)

        tk.Button(
            controls,
            text="Start Navigation",
            command=self.start_navigation
        ).pack(side="left", padx=4)

        tk.Button(
            controls,
            text="Add Obstacle",
            command=self.add_obstacle
        ).pack(side="left", padx=4)

        tk.Button(
            controls,
            text="STOP",
            command=self.stop_navigation
        ).pack(side="left", padx=4)

        tk.Button(
            controls,
            text="Reset",
            command=self.reset
        ).pack(side="left", padx=4)

        self.draw_map()

    def set_status(self, message):
        self.status.config(text=message)
        print(message)

    def draw_map(self):
        self.canvas.delete("all")
        safe = self.controller.safe_grid
        path_cells = set(self.path)

        for r in range(len(self.grid)):
            for c in range(len(self.grid[0])):
                pos = (r, c)

                if pos == self.robot:
                    color = COLORS["robot"]
                elif pos == self.goal:
                    color = COLORS["goal"]
                elif pos in self.new_obstacles:
                    color = COLORS["new_obstacle"]
                elif self.grid[r][c] == 1:
                    color = COLORS["wall"]
                elif safe[r][c] == 1:
                    color = COLORS["clearance"]
                elif pos in path_cells:
                    color = COLORS["path"]
                else:
                    color = COLORS["free"]

                x = c * CELL_SIZE
                y = r * CELL_SIZE

                self.canvas.create_rectangle(
                    x, y,
                    x + CELL_SIZE,
                    y + CELL_SIZE,
                    fill=color,
                    outline="white",
                    width=1
                )

                if pos == self.robot:
                    label = "R"
                elif pos == self.goal:
                    label = "G"
                else:
                    label = None

                if label:
                    self.canvas.create_text(
                        x + CELL_SIZE / 2,
                        y + CELL_SIZE / 2,
                        text=label,
                        fill="white",
                        font=("Arial", 14, "bold")
                    )

    def select_goal(self, event):
        if self.running:
            self.set_status(
                "Stop navigation before selecting a new goal."
            )
            return

        goal = (
            event.y // CELL_SIZE,
            event.x // CELL_SIZE
        )

        if not self.controller.is_safe(goal):
            self.set_status(
                "REJECTED: destination is unsafe."
            )
            return

        route = self.controller.plan_route(
            self.robot, goal
        )

        if route is None:
            self.set_status(
                "BLOCKED: destination is unreachable."
            )
            return

        self.goal = goal
        self.path = route

        self.set_status(
            f"READY | Goal: {goal} | Steps: {len(route)-1}"
        )
        self.draw_map()

    def start_navigation(self):
        if self.running:
            return

        if self.goal is None:
            self.set_status("Select a destination first.")
            return

        route = self.controller.plan_route(
            self.robot, self.goal
        )

        if route is None:
            self.path = []
            self.set_status("BLOCKED: no safe route.")
            self.draw_map()
            return

        self.path = route

        if self.robot == self.goal:
            self.controller.state = NavigationState.ARRIVED
            self.set_status("ARRIVED: already at destination.")
            return

        self.running = True
        self.controller.state = NavigationState.NAVIGATING
        self.set_status("NAVIGATING...")
        self.schedule_step()
        self.draw_map()

    def schedule_step(self):
        if self.running:
            self.job = self.root.after(
                450, self.move_step
            )

    def move_step(self):
        self.job = None

        if not self.running:
            return

        if len(self.path) < 2:
            self.running = False
            self.controller.state = NavigationState.BLOCKED
            self.set_status("BLOCKED: no next step.")
            return

        next_pos = self.path[1]

        if not self.controller.is_safe(next_pos):
            self.set_status(
                "OBSTACLE DETECTED: replanning..."
            )

            if not self.replan():
                return

            next_pos = self.path[1]

        self.robot = next_pos
        self.path = self.path[1:]
        self.draw_map()

        if self.robot == self.goal:
            self.running = False
            self.controller.state = NavigationState.ARRIVED
            self.set_status(
                "ARRIVED: destination reached!"
            )
        else:
            self.schedule_step()

    def replan(self):
        route = self.controller.plan_route(
            self.robot, self.goal
        )

        if route is None or len(route) < 2:
            self.running = False
            self.path = []
            self.controller.state = NavigationState.BLOCKED
            self.set_status(
                "BLOCKED: no alternative route. Robot stopped."
            )
            self.draw_map()
            return False

        self.path = route
        self.controller.state = NavigationState.NAVIGATING
        self.set_status(
            f"REPLANNED: new route has {len(route)-1} steps."
        )
        self.draw_map()
        return True

    def add_obstacle(self):
        if not self.running or len(self.path) < 3:
            self.set_status(
                "Start navigation before adding an obstacle."
            )
            return

        # Block a future path cell, not the robot's cell.
        blocked = self.path[2]

        if blocked == self.goal:
            self.set_status(
                "Cannot place an obstacle on the destination."
            )
            return

        r, c = blocked
        self.grid[r][c] = 1
        self.new_obstacles.add(blocked)

        # Rebuild the inflation map after obstacle insertion.
        self.controller = SafetyController(
            self.grid, clearance=1
        )

        self.set_status(
            f"NEW OBSTACLE at {blocked}. Checking route..."
        )

        # Replan immediately, including newly inflated cells.
        if not self.replan():
            return

    def stop_navigation(self):
        self.running = False

        if self.job is not None:
            self.root.after_cancel(self.job)
            self.job = None

        self.controller.stop()
        self.set_status("STOPPED: navigation cancelled.")

    def reset(self):
        self.stop_navigation()

        self.grid = [
            row.copy() for row in self.original_grid
        ]

        self.controller = SafetyController(
            self.grid, clearance=1
        )

        self.robot = (2, 2)
        self.goal = None
        self.path = []
        self.new_obstacles.clear()

        self.controller.state = NavigationState.IDLE
        self.set_status("RESET: select a safe destination.")
        self.draw_map()


def main():
    root = tk.Tk()
    AutoNavSimulator(root)
    root.mainloop()


if __name__ == "__main__":
    main()
