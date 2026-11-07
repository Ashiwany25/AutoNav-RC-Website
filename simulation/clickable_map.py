
import sys
import tkinter as tk
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.astar import GRID, astar


CELL_SIZE = 65

COLORS = {
    "free": "#E8EFF5",
    "obstacle": "#526174",
    "path": "#F0C35B",
    "robot": "#24946C",
    "goal": "#287BD5",
    "grid": "#FFFFFF",
}


class AutoNavMap:
    def __init__(self, root):
        self.root = root
        self.root.title("AutoNav RC - Interactive Indoor Map")

        self.grid = [row.copy() for row in GRID]
        self.start = (0, 0)
        self.goal = None
        self.path = []

        rows = len(self.grid)
        cols = len(self.grid[0])

        self.canvas = tk.Canvas(
            root,
            width=cols * CELL_SIZE,
            height=rows * CELL_SIZE,
            background="white"
        )
        self.canvas.pack(padx=15, pady=15)

        self.canvas.bind("<Button-1>", self.select_goal)

        self.status = tk.Label(
            root,
            text="Click a free cell to select a destination.",
            font=("Arial", 12)
        )
        self.status.pack(pady=8)

        self.reset_button = tk.Button(
            root,
            text="Reset Destination",
            command=self.reset_goal
        )
        self.reset_button.pack(pady=8)

        self.draw_map()

    def draw_map(self):
        self.canvas.delete("all")

        path_cells = set(self.path)

        for row in range(len(self.grid)):
            for col in range(len(self.grid[0])):
                position = (row, col)

                if position == self.start:
                    color = COLORS["robot"]
                elif position == self.goal:
                    color = COLORS["goal"]
                elif self.grid[row][col] == 1:
                    color = COLORS["obstacle"]
                elif position in path_cells:
                    color = COLORS["path"]
                else:
                    color = COLORS["free"]

                x1 = col * CELL_SIZE
                y1 = row * CELL_SIZE

                self.canvas.create_rectangle(
                    x1, y1,
                    x1 + CELL_SIZE,
                    y1 + CELL_SIZE,
                    fill=color,
                    outline=COLORS["grid"],
                    width=2
                )

                if position == self.start:
                    self.draw_text(row, col, "R")

                elif position == self.goal:
                    self.draw_text(row, col, "G")

    def draw_text(self, row, col, value):
        x = col * CELL_SIZE + CELL_SIZE / 2
        y = row * CELL_SIZE + CELL_SIZE / 2

        self.canvas.create_text(
            x, y,
            text=value,
            fill="white",
            font=("Arial", 18, "bold")
        )

    def select_goal(self, event):
        col = event.x // CELL_SIZE
        row = event.y // CELL_SIZE

        if not (
            0 <= row < len(self.grid)
            and 0 <= col < len(self.grid[0])
        ):
            return

        if self.grid[row][col] != 0:
            self.status.config(
                text="Invalid destination: obstacle detected."
            )
            return

        selected_goal = (row, col)

        path = astar(
            self.grid,
            self.start,
            selected_goal
        )

        if path is None:
            self.status.config(
                text="Destination is unreachable."
            )
            return

        self.goal = selected_goal
        self.path = path

        self.status.config(
            text=(
                f"Destination: {self.goal} | "
                f"Route: {len(path) - 1} steps"
            )
        )

        self.draw_map()

    def reset_goal(self):
        self.goal = None
        self.path = []

        self.status.config(
            text="Click a free cell to select a destination."
        )

        self.draw_map()


def main():
    root = tk.Tk()
    AutoNavMap(root)
    root.mainloop()


if __name__ == "__main__":
    main()
