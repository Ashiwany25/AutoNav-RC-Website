
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.astar import GRID, astar
from simulation.robot_movement import display_robot


def simulate_dynamic_navigation(grid, start, goal):
    """Simulate obstacle detection and automatic replanning."""

    # Copy the map so the original GRID is not modified.
    current_grid = [row.copy() for row in grid]

    robot_position = start
    path = astar(current_grid, robot_position, goal)

    if path is None:
        print("Navigation failed: No valid initial route.")
        return False

    obstacle_added = False
    movement_count = 0

    print("\nAutoNav RC - Dynamic Navigation Started")
    time.sleep(1)

    while robot_position != goal:

        display_robot(
            current_grid,
            robot_position,
            goal,
            path
        )

        print(f"\nMovement count: {movement_count}")

        # Introduce an unexpected obstacle during navigation.
        if movement_count == 3 and not obstacle_added:
            blocked_cell = path[1]

            current_grid[blocked_cell[0]][blocked_cell[1]] = 1
            obstacle_added = True

            print(f"\nOBSTACLE DETECTED at {blocked_cell}!")
            print("Stopping and recalculating route...")

            path = astar(
                current_grid,
                robot_position,
                goal
            )

            if path is None:
                print("No alternative route available.")
                print("ROBOT STOPPED SAFELY.")
                return False

            print("New route calculated successfully!")
            time.sleep(2)

        if len(path) < 2:
            print("No next movement available.")
            return False

        next_position = path[1]

        # Never move into a blocked cell.
        if current_grid[next_position[0]][next_position[1]] == 1:
            print("Obstacle directly ahead. Replanning...")
            path = astar(current_grid, robot_position, goal)

            if path is None:
                print("ROBOT STOPPED SAFELY.")
                return False

            continue

        robot_position = next_position
        movement_count += 1

        # Remove the visited position from the current path.
        path = path[1:]

        time.sleep(0.7)

    display_robot(
        current_grid,
        robot_position,
        goal,
        path
    )

    print("\nDESTINATION REACHED SUCCESSFULLY!")
    print(f"Total movements: {movement_count}")

    return True


def main():
    start = (0, 0)
    goal = (6, 6)

    simulate_dynamic_navigation(GRID, start, goal)


if __name__ == "__main__":
    main()
