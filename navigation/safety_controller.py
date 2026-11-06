
from enum import Enum

from navigation.astar import astar


class NavigationState(Enum):
    IDLE = "IDLE"
    PLANNING = "PLANNING"
    READY = "READY"
    NAVIGATING = "NAVIGATING"
    ARRIVED = "ARRIVED"
    BLOCKED = "BLOCKED"
    STOPPED = "STOPPED"


class SafetyController:

    def __init__(self, grid, clearance=1):
        self.grid = [row.copy() for row in grid]
        self.clearance = clearance
        self.state = NavigationState.IDLE
        self.path = None

        if not self.grid or not self.grid[0]:
            raise ValueError("Map cannot be empty")

        width = len(self.grid[0])

        if any(len(row) != width for row in self.grid):
            raise ValueError("Map must be rectangular")

        if clearance < 0 or not isinstance(clearance, int):
            raise ValueError("Clearance must be >= 0")

        self.safe_grid = self.inflate_obstacles()

    def inflate_obstacles(self):
        """
        Expand walls by a safety clearance.

        0 = free
        1 = blocked
        -1 = unknown, treated as blocked
        """

        rows = len(self.grid)
        cols = len(self.grid[0])

        safe = [
            [0 for _ in range(cols)]
            for _ in range(rows)
        ]

        for r in range(rows):
            for c in range(cols):

                if self.grid[r][c] != 0:
                    safe[r][c] = 1
                    continue

                for dr in range(
                    -self.clearance,
                    self.clearance + 1
                ):
                    for dc in range(
                        -self.clearance,
                        self.clearance + 1
                    ):
                        nr = r + dr
                        nc = c + dc

                        if nr < 0 or nr >= rows:
                            safe[r][c] = 1
                            break

                        if nc < 0 or nc >= cols:
                            safe[r][c] = 1
                            break

                        if self.grid[nr][nc] != 0:
                            safe[r][c] = 1
                            break

                    if safe[r][c] == 1:
                        break

        return safe

    def is_safe(self, position):

        r, c = position

        if not (0 <= r < len(self.safe_grid)):
            return False

        if not (0 <= c < len(self.safe_grid[0])):
            return False

        return self.safe_grid[r][c] == 0

    def plan_route(self, start, goal):

        self.path = None
        self.state = NavigationState.PLANNING

        if not self.is_safe(start):
            self.state = NavigationState.BLOCKED
            print("Unsafe starting position.")
            return None

        if not self.is_safe(goal):
            self.state = NavigationState.BLOCKED
            print("Unsafe destination.")
            return None

        route = astar(self.safe_grid, start, goal)

        if route is None:
            self.state = NavigationState.BLOCKED
            print("No collision-free route found.")
            return None

        self.path = route
        self.state = NavigationState.READY

        return route

    def stop(self):
        self.state = NavigationState.STOPPED
        self.path = None


def main():

    # Larger test map with open space.
    grid = [
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0],
    ]

    controller = SafetyController(
        grid,
        clearance=1
    )

    print("\n===== AUTONAV RC SAFETY SYSTEM =====")

    print("\nSafety map:")
    for row in controller.safe_grid:
        print(" ".join(
            "#" if cell == 1 else "."
            for cell in row
        ))

    start = (1, 1)
    goal = (7, 7)

    print("\nPlanning route...")
    path = controller.plan_route(start, goal)

    print("Navigation state:", controller.state.value)

    if path:
        print("Safe path found!")
        print("Path:", path)
        print("Path length:", len(path) - 1)

    print("\nTesting unsafe destination...")
    controller.plan_route(start, (4, 4))

    print("Navigation state:", controller.state.value)

    print("\nTesting stop...")
    controller.stop()

    print("Navigation state:", controller.state.value)


if __name__ == "__main__":
    main()
