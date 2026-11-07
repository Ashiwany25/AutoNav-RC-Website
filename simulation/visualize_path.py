
import sys
from pathlib import Path

# Allow importing modules from the project root.
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.astar import GRID, astar


def display_map(grid, start, goal, path):
    """Display the planned path on a simulated indoor grid."""

    path_cells = set(path or [])

    print("\n========== AUTONAV RC ==========")
    print("     INDOOR PATH SIMULATION")
    print("================================\n")

    for r in range(len(grid)):
        row_symbols = []

        for c in range(len(grid[0])):
            position = (r, c)

            if position == start:
                symbol = "S"
            elif position == goal:
                symbol = "G"
            elif grid[r][c] == 1:
                symbol = "█"
            elif position in path_cells:
                symbol = "●"
            else:
                symbol = "·"

            row_symbols.append(symbol)

        print("  ".join(row_symbols))

    print("\nLegend:")
    print("S = Starting position")
    print("G = Destination")
    print("█ = Obstacle")
    print("● = Planned route")
    print("· = Free space")

    if path:
        print(f"\nPath successfully calculated!")
        print(f"Total movement steps: {len(path) - 1}")
    else:
        print("\nNo valid route available.")


def main():
    start = (0, 0)
    goal = (6, 6)

    path = astar(GRID, start, goal)

    display_map(GRID, start, goal, path)


if __name__ == "__main__":
    main()

