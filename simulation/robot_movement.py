
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.astar import GRID, astar


def display_robot(grid, robot, goal, path):
    """Display the robot's current position on the map."""

    path_cells = set(path or [])

    print("\033[2J\033[H", end="", flush=True)

    print("================================")
    print("      AUTONAV RC SIMULATION")
    print("================================\n")

    for row in range(len(grid)):
        symbols = []

        for col in range(len(grid[0])):
            position = (row, col)

            if position == robot:
                symbol = "R"
            elif position == goal:
                symbol = "G"
            elif grid[row][col] == 1:
                symbol = "█"
            elif position in path_cells:
                symbol = "●"
            else:
                symbol = "·"

            symbols.append(symbol)

        print("  ".join(symbols))

    print("\nR = Robot | G = Goal | █ = Obstacle")
    print("● = Planned route | · = Free space")
    print(f"\nRobot position: {robot}")
    print(f"Destination: {goal}", flush=True)


def simulate_movement(grid, start, goal):
    """Move the simulated robot along an A* path."""

    path = astar(grid, start, goal)

    if path is None:
        print("Navigation failed: no valid route.")
        return False

    print(f"Route found: {len(path) - 1} movement steps")
    time.sleep(1)

    for step, position in enumerate(path):
        display_robot(grid, position, goal, path)

        print(f"\nMovement step: {step}/{len(path) - 1}")

        if position == goal:
            print("\nDESTINATION REACHED!")
            return True

        time.sleep(0.7)

    return False


def main():
    start = (0, 0)

    print("================================")
    print("    AUTONAV RC ROBOT MOVEMENT")
    print("================================")

    while True:
        try:
            row = int(input("\nDestination row (0-6): "))
            col = int(input("Destination column (0-6): "))
        except ValueError:
            print("Please enter valid integers.")
            continue

        goal = (row, col)

        path = astar(GRID, start, goal)

        if path is None:
            print("Invalid or unreachable destination.")
            continue

        print("\nStarting autonomous movement simulation...")
        simulate_movement(GRID, start, goal)
        break


if __name__ == "__main__":
    main()
