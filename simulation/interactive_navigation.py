
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.astar import GRID, astar
from simulation.visualize_path import display_map


def is_valid_destination(grid, row, col):
    """Check that the destination is inside the map and free."""

    if row < 0 or row >= len(grid):
        return False

    if col < 0 or col >= len(grid[0]):
        return False

    if grid[row][col] != 0:
        return False

    return True


def get_destination(grid):
    """Ask the user to select a destination."""

    while True:
        print("\nEnter your destination coordinates.")

        try:
            row = int(input("Destination row (0-6): "))
            col = int(input("Destination column (0-6): "))

        except ValueError:
            print("Invalid input! Please enter whole numbers.")
            continue

        if not is_valid_destination(grid, row, col):
            print("Invalid destination!")
            print("Choose a free cell inside the map.")
            continue

        return row, col


def main():
    start = (0, 0)

    print("\n================================")
    print("       AUTONAV RC SYSTEM")
    print("    INTERACTIVE NAVIGATION")
    print("================================")

    display_map(GRID, start, start, [])

    while True:
        goal = get_destination(GRID)

        path = astar(GRID, start, goal)

        if path is None:
            print("\nDestination cannot be reached.")
        else:
            print("\nRoute calculated successfully!")

        display_map(GRID, start, goal, path)

        choice = input(
            "\nSelect another destination? (y/n): "
        ).strip().lower()

        if choice != "y":
            print("\nAutoNav RC simulation stopped.")
            break


if __name__ == "__main__":
    main()
