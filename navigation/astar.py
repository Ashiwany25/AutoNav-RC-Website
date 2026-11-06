
import heapq
from math import inf

# 0 = free space
# 1 = obstacle
# Coordinates are (row, column).

GRID = [
    [0, 0, 0, 0, 0, 0, 0],
    [0, 1, 1, 1, 0, 1, 0],
    [0, 0, 0, 1, 0, 1, 0],
    [0, 1, 0, 0, 0, 1, 0],
    [0, 1, 0, 1, 0, 0, 0],
    [0, 0, 0, 1, 0, 1, 0],
    [0, 1, 0, 0, 0, 0, 0],
]


def heuristic(a, b):
    """Manhattan distance for four-direction movement."""
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def astar(grid, start, goal):
    """Find a collision-free path through a binary grid."""

    if not grid or not grid[0]:
        return None

    rows = len(grid)
    cols = len(grid[0])

    if any(len(row) != cols for row in grid):
        raise ValueError("Grid must be rectangular")

    def is_free(point):
        r, c = point
        return (
            0 <= r < rows
            and 0 <= c < cols
            and grid[r][c] == 0
        )

    if not is_free(start) or not is_free(goal):
        return None

    open_set = [(heuristic(start, goal), 0, start)]
    came_from = {}
    g_score = {start: 0}

    directions = [
        (0, 1),
        (1, 0),
        (0, -1),
        (-1, 0),
    ]

    while open_set:
        _, cost, current = heapq.heappop(open_set)

        # Ignore outdated priority-queue entries.
        if cost != g_score.get(current, inf):
            continue

        if current == goal:
            path = [current]

            while current in came_from:
                current = came_from[current]
                path.append(current)

            return path[::-1]

        for dr, dc in directions:
            neighbor = (
                current[0] + dr,
                current[1] + dc,
            )

            if not is_free(neighbor):
                continue

            tentative_cost = cost + 1

            if tentative_cost < g_score.get(neighbor, inf):
                came_from[neighbor] = current
                g_score[neighbor] = tentative_cost

                priority = (
                    tentative_cost + heuristic(neighbor, goal)
                )

                heapq.heappush(
                    open_set,
                    (priority, tentative_cost, neighbor),
                )

    return None


if __name__ == "__main__":
    start = (0, 0)
    goal = (6, 6)

    path = astar(GRID, start, goal)

    if path is None:
        print("No valid path found.")
    else:
        print("Path found!")
        print("Start:", start)
        print("Goal:", goal)
        print("Path length:", len(path) - 1, "steps")
        print("Path:", path)
