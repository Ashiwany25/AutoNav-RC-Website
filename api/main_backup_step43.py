
import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
import sys

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.safety_controller import (
    SafetyController,
    NavigationState,
)


def create_test_map():
    """Temporary simulated indoor environment."""
    grid = [[0] * 15 for _ in range(15)]

    for row in range(4, 11):
        grid[row][6] = 1

    for col in range(9, 13):
        grid[9][col] = 1

    return grid


class Position(BaseModel):
    row: int = Field(ge=0)
    col: int = Field(ge=0)


class PlanRequest(BaseModel):
    goal: Position


class RobotStatus(BaseModel):
    device_id: str
    mode: str
    connected: bool
    position: Position
    navigation_state: str
    simulation: bool


class SimulationRobot:
    def __init__(self):
        self.grid = create_test_map()
        self.controller = SafetyController(
            self.grid,
            clearance=1
        )

        self.position = (2, 2)
        self.goal = None
        self.path = []
        self.mode = "IDLE"
        self.device_id = "AUTONAV-SIM-001"

        self.current_step = 0
        self.total_steps = 0
        self.task = None
        self.lock = asyncio.Lock()

    async def execute_navigation(self):
        """Move along the planned route in simulation."""

        try:
            while True:
                await asyncio.sleep(0.5)

                async with self.lock:
                    if self.mode != "NAVIGATING":
                        return

                    if len(self.path) < 2:
                        self.mode = "BLOCKED"
                        self.controller.state = NavigationState.BLOCKED
                        return

                    next_position = self.path[1]

                    if not self.controller.is_safe(next_position):
                        self.mode = "BLOCKED"
                        self.controller.state = NavigationState.BLOCKED
                        return

                    self.position = next_position
                    self.path = self.path[1:]
                    self.current_step += 1

                    if self.position == self.goal:
                        self.mode = "ARRIVED"
                        self.controller.state = NavigationState.ARRIVED
                        return

        except asyncio.CancelledError:
            return


robot = SimulationRobot()


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("AutoNav API v1 started")
    yield

    if robot.task and not robot.task.done():
        robot.task.cancel()
        try:
            await robot.task
        except asyncio.CancelledError:
            pass

    print("AutoNav API v1 stopped")


app = FastAPI(
    title="AutoNav API",
    description="Local API for AutoNav RC simulation.",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/api/v1/health")
async def health():
    return {
        "success": True,
        "service": "AutoNav API",
        "version": "1.0.0",
        "status": "online",
        "simulation": True,
        "timestamp": datetime.now(
            timezone.utc
        ).isoformat(),
    }


@app.get("/api/v1/robot/status")
async def get_robot_status():
    async with robot.lock:
        return RobotStatus(
            device_id=robot.device_id,
            mode=robot.mode,
            connected=True,
            position=Position(
                row=robot.position[0],
                col=robot.position[1],
            ),
            navigation_state=robot.controller.state.value,
            simulation=True,
        )


@app.post("/api/v1/navigation/plan")
async def plan_navigation(request: PlanRequest):
    goal = (request.goal.row, request.goal.col)

    async with robot.lock:
        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail="Cannot plan while robot is navigating."
            )

        if not robot.controller.is_safe(goal):
            raise HTTPException(
                status_code=400,
                detail="Destination is unsafe or outside map."
            )

        path = robot.controller.plan_route(
            robot.position, goal
        )

        if path is None:
            raise HTTPException(
                status_code=409,
                detail="No safe route available."
            )

        return {
            "success": True,
            "simulation": True,
            "start": {
                "row": robot.position[0],
                "col": robot.position[1],
            },
            "goal": request.goal.model_dump(),
            "path": [
                {"row": row, "col": col}
                for row, col in path
            ],
            "steps": len(path) - 1,
            "navigation_state": robot.controller.state.value,
            "message": "Route planned successfully.",
        }


@app.post("/api/v1/navigation/start")
async def start_navigation(request: PlanRequest):
    goal = (request.goal.row, request.goal.col)

    async with robot.lock:
        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail="Robot is already navigating."
            )

        if robot.task and not robot.task.done():
            raise HTTPException(
                status_code=409,
                detail="Previous navigation task is still stopping."
            )

        if not robot.controller.is_safe(goal):
            raise HTTPException(
                status_code=400,
                detail="Destination is unsafe."
            )

        path = robot.controller.plan_route(
            robot.position, goal
        )

        if path is None:
            raise HTTPException(
                status_code=409,
                detail="No safe route available."
            )

        robot.goal = goal
        robot.path = path
        robot.current_step = 0
        robot.total_steps = len(path) - 1

        if robot.position == goal:
            robot.mode = "ARRIVED"
            robot.controller.state = NavigationState.ARRIVED
        else:
            robot.mode = "NAVIGATING"
            robot.controller.state = NavigationState.NAVIGATING
            robot.task = asyncio.create_task(
                robot.execute_navigation()
            )

        return {
            "success": True,
            "simulation": True,
            "navigation_state": robot.mode,
            "total_steps": robot.total_steps,
            "message": "Navigation request accepted.",
        }


@app.post("/api/v1/navigation/stop")
async def stop_navigation():
    async with robot.lock:
        robot.mode = "STOPPED"
        robot.controller.stop()
        robot.path = []

        task = robot.task

        if task and not task.done():
            task.cancel()

    if task and not task.done():
        try:
            await task
        except asyncio.CancelledError:
            pass

    return {
        "success": True,
        "simulation": True,
        "navigation_state": "STOPPED",
        "message": "Simulated navigation stopped.",
    }


@app.get("/api/v1/navigation/status")
async def navigation_status():
    async with robot.lock:
        return {
            "success": True,
            "simulation": True,
            "navigation_state": robot.mode,
            "position": {
                "row": robot.position[0],
                "col": robot.position[1],
            },
            "goal": (
                {
                    "row": robot.goal[0],
                    "col": robot.goal[1],
                }
                if robot.goal else None
            ),
            "current_step": robot.current_step,
            "total_steps": robot.total_steps,
            "remaining_steps": len(robot.path) - 1
            if robot.path else 0,
        }


@app.get("/api/v1/maps/current")
async def get_current_map():
    """
    Return the current simulated occupancy grid.

    Cell values:
    0 = Free space
    1 = Obstacle
    """

    async with robot.lock:
        rows = len(robot.grid)
        cols = len(robot.grid[0])

        return {
            "success": True,
            "simulation": True,
            "map_id": "AUTONAV-SIM-MAP-001",
            "map_name": "Simulation Indoor Map",
            "map_type": "occupancy_grid",
            "resolution": 0.10,
            "resolution_unit": "meters_per_cell",
            "width": cols,
            "height": rows,
            "origin": {
                "x": 0.0,
                "y": 0.0
            },
            "grid": [
                row.copy() for row in robot.grid
            ],
            "robot_position": {
                "row": robot.position[0],
                "col": robot.position[1]
            },
            "legend": {
                "0": "free",
                "1": "occupied"
            }
        }
