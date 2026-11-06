
import asyncio
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from mapping.teach_mode import (
    TeachModeMapper,
    FREE,
    OCCUPIED,
)


ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data" / "teach_maps" / "latest_map.json"

SENSOR_RANGE_CELLS = 3
OBSTACLE_CLEARANCE_CELLS = 1

DIRECTIONS = {
    "UP": (-1, 0),
    "DOWN": (1, 0),
    "LEFT": (0, -1),
    "RIGHT": (0, 1),
}


class MoveRequest(BaseModel):
    direction: str
    steps: int = Field(default=1, ge=1, le=1)


def simulated_sensor_observations(
    grid,
    position,
    radius=SENSOR_RANGE_CELLS,
):
    height = len(grid)
    width = len(grid[0])

    start_row, start_col = position
    observations = {}

    def cast_ray(end_row, end_col):
        row, col = start_row, start_col

        dr = abs(end_row - start_row)
        dc = abs(end_col - start_col)

        sr = 1 if start_row < end_row else -1
        sc = 1 if start_col < end_col else -1

        error = dr - dc

        while True:
            if not (
                0 <= row < height
                and 0 <= col < width
            ):
                return

            value = grid[row][col]

            observations[(row, col)] = (
                OCCUPIED if value == 1 else FREE
            )

            if value == 1:
                return

            if row == end_row and col == end_col:
                return

            twice_error = 2 * error

            if twice_error > -dc:
                error -= dc
                row += sr

            if twice_error < dr:
                error += dr
                col += sc

    for offset in range(-radius, radius + 1):
        cast_ray(
            start_row - radius,
            start_col + offset,
        )
        cast_ray(
            start_row + radius,
            start_col + offset,
        )
        cast_ray(
            start_row + offset,
            start_col - radius,
        )
        cast_ray(
            start_row + offset,
            start_col + radius,
        )

    return [
        {"row": row, "col": col, "value": value}
        for (row, col), value in sorted(
            observations.items()
        )
    ]


def safe_position(grid, row, col):
    height = len(grid)
    width = len(grid[0])

    if not (0 <= row < height and 0 <= col < width):
        return False

    if grid[row][col] != 0:
        return False

    for dr in range(
        -OBSTACLE_CLEARANCE_CELLS,
        OBSTACLE_CLEARANCE_CELLS + 1,
    ):
        for dc in range(
            -OBSTACLE_CLEARANCE_CELLS,
            OBSTACLE_CLEARANCE_CELLS + 1,
        ):
            nr = row + dr
            nc = col + dc

            if 0 <= nr < height and 0 <= nc < width:
                if grid[nr][nc] != 0:
                    return False

    return True


def create_teach_router(robot, save_path=MAP_PATH):
    router = APIRouter(
        prefix="/api/v1/teach",
        tags=["Teach Mode"],
    )

    lock = asyncio.Lock()
    save_path = Path(save_path)

    mapper = None
    active = False
    exploration_position = None
    unique_explored_cells = 0

    async def get_simulation_state():
        async with robot.lock:
            if robot.mode in ("MANUAL", "NAVIGATING"):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Stop Manual Control or Auto Navigation "
                        "before exploring in Teach Mode."
                    ),
                )

            task = getattr(robot, "task", None)

            if task is not None and not task.done():
                raise HTTPException(
                    status_code=409,
                    detail="Navigation task is still running.",
                )

            return (
                [row.copy() for row in robot.grid],
                tuple(robot.position),
            )

    def get_mapper():
        if mapper is not None:
            return mapper

        if save_path.exists():
            try:
                return TeachModeMapper.load(save_path)
            except (
                ValueError,
                KeyError,
                TypeError,
                OSError,
            ) as error:
                raise HTTPException(
                    status_code=500,
                    detail=f"Saved map invalid: {error}",
                ) from error

        raise HTTPException(
            status_code=404,
            detail="No Teach Mode map available.",
        )

    def map_payload(selected):
        payload = selected.to_dict()

        return {
            **payload,
            "unique_explored_cells": sum(
                cell != -1
                for row in selected.grid
                for cell in row
            ),
        }

    @router.post("/start")
    async def start_teach_mode():
        nonlocal mapper
        nonlocal active
        nonlocal exploration_position
        nonlocal unique_explored_cells

        async with lock:
            if active:
                raise HTTPException(
                    status_code=409,
                    detail="Teach Mode is already active.",
                )

            grid, position = await get_simulation_state()

            if not safe_position(grid, *position):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Starting position does not satisfy "
                        "the obstacle clearance requirement."
                    ),
                )

            mapper = TeachModeMapper(
                width=len(grid[0]),
                height=len(grid),
                resolution=0.10,
            )

            exploration_position = position
            mapper.update_robot_position(*position)

            unique_explored_cells = 0
            active = True

            return {
                "success": True,
                "simulation": True,
                "teach_active": True,
                "map": map_payload(mapper),
            }

    @router.post("/move")
    async def move_in_teach_mode(
        command: MoveRequest,
    ):
        nonlocal exploration_position

        async with lock:
            if not active or mapper is None:
                raise HTTPException(
                    status_code=409,
                    detail="Start Teach Mode first.",
                )

            direction = command.direction.upper()

            if direction not in DIRECTIONS:
                raise HTTPException(
                    status_code=422,
                    detail="Use UP, DOWN, LEFT or RIGHT.",
                )

            grid, _ = await get_simulation_state()

            dr, dc = DIRECTIONS[direction]

            current_row, current_col = exploration_position

            new_row = current_row + dr
            new_col = current_col + dc

            if not safe_position(
                grid,
                new_row,
                new_col,
            ):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Movement blocked: obstacle, "
                        "safety clearance, or map boundary."
                    ),
                )

            exploration_position = (
                new_row,
                new_col,
            )

            mapper.update_robot_position(
                new_row,
                new_col,
            )

            return {
                "success": True,
                "simulation": True,
                "direction": direction,
                "moved": True,
                "robot_position": {
                    "row": new_row,
                    "col": new_col,
                },
                "map": map_payload(mapper),
            }

    @router.post("/observe")
    async def observe_environment():
        nonlocal unique_explored_cells

        async with lock:
            if not active or mapper is None:
                raise HTTPException(
                    status_code=409,
                    detail="Teach Mode is not active.",
                )

            grid, _ = await get_simulation_state()

            observations = simulated_sensor_observations(
                grid,
                exploration_position,
            )

            before = sum(
                cell != -1
                for row in mapper.grid
                for cell in row
            )

            mapper.add_observations(observations)

            mapper.update_robot_position(
                *exploration_position
            )

            after = sum(
                cell != -1
                for row in mapper.grid
                for cell in row
            )

            unique_explored_cells = after

            return {
                "success": True,
                "simulation": True,
                "teach_active": True,
                "observed_cells": len(observations),
                "new_cells": after - before,
                "unique_explored_cells": after,
                "exploration_percentage": (
                    mapper.exploration_percentage()
                ),
                "map": map_payload(mapper),
            }

    @router.post("/finish")
    async def finish_teach_mode():
        nonlocal active

        async with lock:
            if not active or mapper is None:
                raise HTTPException(
                    status_code=409,
                    detail="Teach Mode is not active.",
                )

            saved_path = mapper.save(save_path)
            active = False

            return {
                "success": True,
                "simulation": True,
                "teach_active": False,
                "saved": True,
                "saved_path": saved_path,
                "exploration_percentage": (
                    mapper.exploration_percentage()
                ),
            }

    @router.get("/map")
    async def get_teach_map():
        async with lock:
            selected = get_mapper()

            return {
                "success": True,
                "simulation": True,
                "teach_active": active,
                "saved": not active and save_path.exists(),
                **map_payload(selected),
            }

    @router.get("/status")
    async def get_teach_status():
        async with lock:
            has_map = mapper is not None or save_path.exists()

            if has_map:
                selected = get_mapper()
                percentage = selected.exploration_percentage()
                count = selected.observation_count
            else:
                percentage = 0.0
                count = 0

            return {
                "success": True,
                "simulation": True,
                "teach_active": active,
                "map_available": has_map,
                "saved_map_available": save_path.exists(),
                "exploration_percentage": percentage,
                "observation_count": count,
            }

    return router
