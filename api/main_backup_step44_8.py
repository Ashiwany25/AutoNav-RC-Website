
import asyncio
import sys
import time

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.safety_controller import (
    SafetyController,
    NavigationState,
)


# --------------------------------------------------
# SIMULATED INDOOR MAP
# --------------------------------------------------

def create_test_map():
    """Temporary 15 x 15 indoor occupancy grid."""
    grid = [[0] * 15 for _ in range(15)]

    for row in range(4, 11):
        grid[row][6] = 1

    for col in range(9, 13):
        grid[9][col] = 1

    return grid


# --------------------------------------------------
# API MODELS
# --------------------------------------------------

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


class ManualDriveRequest(BaseModel):
    direction: Literal[
        "FORWARD",
        "BACKWARD",
        "LEFT",
        "RIGHT",
    ]

    speed: int = Field(
        default=40,
        ge=0,
        le=100,
    )


# --------------------------------------------------
# MANUAL CONTROL SETTINGS
# --------------------------------------------------

# Manual commands must be renewed frequently.
# This is a simulated command watchdog, not
# a substitute for an ESP32 motor watchdog.

MANUAL_TIMEOUT_SECONDS = 0.6
WATCHDOG_CHECK_SECONDS = 0.1


# --------------------------------------------------
# SIMULATED ROBOT
# --------------------------------------------------

class SimulationRobot:
    def __init__(self):
        self.grid = create_test_map()

        # Preserve the existing obstacle clearance.
        self.controller = SafetyController(
            self.grid,
            clearance=1,
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

        # Manual Control state.
        self.manual_direction = "STOPPED"
        self.manual_speed = 0
        self.manual_deadline = 0.0

        self.watchdog_task = None

    def clear_manual_command(self):
        """Clear manual input while holding robot.lock."""
        self.manual_direction = "STOPPED"
        self.manual_speed = 0
        self.manual_deadline = 0.0

    def stop_all_locked(self):
        """
        Set simulation into STOPPED state.

        Must be called while holding robot.lock.
        The caller handles awaiting canceled tasks.
        """
        self.mode = "STOPPED"
        self.controller.stop()

        self.path = []
        self.goal = None

        self.clear_manual_command()

        task = self.task

        if task is not None and not task.done():
            task.cancel()

        return task

    async def execute_navigation(self):
        """Move along a planned A* route in simulation."""
        try:
            while True:
                await asyncio.sleep(0.5)

                async with self.lock:
                    if self.mode != "NAVIGATING":
                        return

                    if len(self.path) < 2:
                        self.mode = "BLOCKED"
                        self.controller.state = (
                            NavigationState.BLOCKED
                        )
                        return

                    next_position = self.path[1]

                    if not self.controller.is_safe(
                        next_position
                    ):
                        self.mode = "BLOCKED"
                        self.controller.state = (
                            NavigationState.BLOCKED
                        )
                        return

                    self.position = next_position

                    self.path = self.path[1:]
                    self.current_step += 1

                    if self.position == self.goal:
                        self.mode = "ARRIVED"
                        self.controller.state = (
                            NavigationState.ARRIVED
                        )
                        return

        except asyncio.CancelledError:
            return

    async def manual_watchdog(self):
        """
        Expire manual commands when refreshes stop.

        This updates simulator command state only.
        It does not command real motors.
        """
        try:
            while True:
                await asyncio.sleep(
                    WATCHDOG_CHECK_SECONDS
                )

                async with self.lock:
                    if self.mode != "MANUAL":
                        continue

                    if time.monotonic() >= (
                        self.manual_deadline
                    ):
                        self.stop_all_locked()

        except asyncio.CancelledError:
            return


robot = SimulationRobot()


# --------------------------------------------------
# SERVER LIFESPAN
# --------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("AutoNav API v1 started")

    robot.watchdog_task = asyncio.create_task(
        robot.manual_watchdog()
    )

    yield

    # Stop simulated commands during shutdown.
    async with robot.lock:
        robot.stop_all_locked()

        tasks = [
            task
            for task in [
                robot.task,
                robot.watchdog_task,
            ]
            if task is not None and not task.done()
        ]

        for task in tasks:
            task.cancel()

    if tasks:
        await asyncio.gather(
            *tasks,
            return_exceptions=True,
        )

    print("AutoNav API v1 stopped")


app = FastAPI(
    title="AutoNav API",
    description=(
        "Local API for AutoNav RC simulation."
    ),
    version="1.0.0",
    lifespan=lifespan,
)


# --------------------------------------------------
# EXISTING HEALTH ENDPOINT
# --------------------------------------------------

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


# --------------------------------------------------
# EXISTING ROBOT STATUS ENDPOINT
# --------------------------------------------------

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
            navigation_state=(
                robot.controller.state.value
            ),
            simulation=True,
        )


# --------------------------------------------------
# EXISTING A* ROUTE PLANNING
# --------------------------------------------------

@app.post("/api/v1/navigation/plan")
async def plan_navigation(
    request: PlanRequest,
):
    goal = (
        request.goal.row,
        request.goal.col,
    )

    async with robot.lock:
        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Cannot plan while robot "
                    "is navigating."
                ),
            )

        if robot.mode == "MANUAL":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Stop manual control before "
                    "autonomous navigation."
                ),
            )

        if not robot.controller.is_safe(goal):
            raise HTTPException(
                status_code=400,
                detail=(
                    "Destination is unsafe "
                    "or outside map."
                ),
            )

        path = robot.controller.plan_route(
            robot.position,
            goal,
        )

        if path is None:
            raise HTTPException(
                status_code=409,
                detail="No safe route available.",
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
                {
                    "row": row,
                    "col": col,
                }
                for row, col in path
            ],
            "steps": len(path) - 1,
            "navigation_state": (
                robot.controller.state.value
            ),
            "message": (
                "Route planned successfully."
            ),
        }


# --------------------------------------------------
# EXISTING AUTONOMOUS NAVIGATION START
# --------------------------------------------------

@app.post("/api/v1/navigation/start")
async def start_navigation(
    request: PlanRequest,
):
    goal = (
        request.goal.row,
        request.goal.col,
    )

    async with robot.lock:
        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail="Robot is already navigating.",
            )

        if robot.mode == "MANUAL":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Stop manual control before "
                    "starting navigation."
                ),
            )

        if robot.task and not robot.task.done():
            raise HTTPException(
                status_code=409,
                detail=(
                    "Previous navigation task "
                    "is still stopping."
                ),
            )

        if not robot.controller.is_safe(goal):
            raise HTTPException(
                status_code=400,
                detail="Destination is unsafe.",
            )

        path = robot.controller.plan_route(
            robot.position,
            goal,
        )

        if path is None:
            raise HTTPException(
                status_code=409,
                detail="No safe route available.",
            )

        robot.clear_manual_command()

        robot.goal = goal
        robot.path = path

        robot.current_step = 0
        robot.total_steps = len(path) - 1

        if robot.position == goal:
            robot.mode = "ARRIVED"

            robot.controller.state = (
                NavigationState.ARRIVED
            )

        else:
            robot.mode = "NAVIGATING"

            robot.controller.state = (
                NavigationState.NAVIGATING
            )

            robot.task = asyncio.create_task(
                robot.execute_navigation()
            )

        return {
            "success": True,
            "simulation": True,
            "navigation_state": robot.mode,
            "total_steps": robot.total_steps,
            "message": (
                "Navigation request accepted."
            ),
        }


# --------------------------------------------------
# EXISTING AUTONOMOUS STOP
# --------------------------------------------------

@app.post("/api/v1/navigation/stop")
async def stop_navigation():
    async with robot.lock:
        task = robot.stop_all_locked()

    if task and not task.done():
        try:
            await task
        except asyncio.CancelledError:
            pass

    return {
        "success": True,
        "simulation": True,
        "navigation_state": "STOPPED",
        "message": (
            "Simulated navigation stopped."
        ),
    }


# --------------------------------------------------
# EXISTING AUTONOMOUS NAVIGATION STATUS
# --------------------------------------------------

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
            "remaining_steps": (
                max(0, len(robot.path) - 1)
                if robot.path else 0
            ),
        }


# --------------------------------------------------
# EXISTING CURRENT MAP ENDPOINT
# --------------------------------------------------

@app.get("/api/v1/maps/current")
async def get_current_map():
    """
    Return the current simulated occupancy grid.

    0 = free space
    1 = occupied cell
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
                "y": 0.0,
            },
            "grid": [
                row.copy()
                for row in robot.grid
            ],
            "robot_position": {
                "row": robot.position[0],
                "col": robot.position[1],
            },
            "legend": {
                "0": "free",
                "1": "occupied",
            },
        }


# --------------------------------------------------
# NEW: MANUAL DRIVE API
# --------------------------------------------------

@app.post("/api/v1/manual/drive")
async def manual_drive(
    request: ManualDriveRequest,
):
    """
    Accept one simulated manual drive command.

    The client must keep renewing the command
    while the user holds a direction button.
    """
    async with robot.lock:
        # Never interrupt autonomous navigation
        # with an ordinary manual drive request.
        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Autonomous navigation is active. "
                    "Stop navigation first."
                ),
            )

        if robot.task and not robot.task.done():
            raise HTTPException(
                status_code=409,
                detail=(
                    "Previous navigation task "
                    "is still stopping."
                ),
            )

        robot.mode = "MANUAL"

        # Do not retain an autonomous route.
        robot.controller.stop()
        robot.path = []
        robot.goal = None

        robot.manual_direction = request.direction
        robot.manual_speed = request.speed

        robot.manual_deadline = (
            time.monotonic()
            + MANUAL_TIMEOUT_SECONDS
        )

        return {
            "success": True,
            "simulation": True,
            "mode": robot.mode,
            "direction": robot.manual_direction,
            "speed": robot.manual_speed,
            "timeout_ms": int(
                MANUAL_TIMEOUT_SECONDS * 1000
            ),
            "message": (
                "Simulated manual command accepted."
            ),
        }


# --------------------------------------------------
# NEW: MANUAL STOP API
# --------------------------------------------------

@app.post("/api/v1/manual/stop")
async def manual_stop():
    """
    Stop manual simulation.

    Also cancels autonomous movement if active.
    The STOP endpoint takes priority over modes.
    """
    async with robot.lock:
        task = robot.stop_all_locked()

    if task and not task.done():
        try:
            await task
        except asyncio.CancelledError:
            pass

    return {
        "success": True,
        "simulation": True,
        "mode": "STOPPED",
        "direction": "STOPPED",
        "speed": 0,
        "message": (
            "Simulated robot stopped."
        ),
    }


# --------------------------------------------------
# NEW: MANUAL STATUS API
# --------------------------------------------------

@app.get("/api/v1/manual/status")
async def manual_status():
    async with robot.lock:
        remaining_ms = 0

        if robot.mode == "MANUAL":
            remaining_ms = max(
                0,
                int(
                    (
                        robot.manual_deadline
                        - time.monotonic()
                    ) * 1000
                ),
            )

        return {
            "success": True,
            "simulation": True,
            "mode": robot.mode,
            "direction": robot.manual_direction,
            "speed": robot.manual_speed,
            "command_remaining_ms": remaining_ms,
            "position": {
                "row": robot.position[0],
                "col": robot.position[1],
            },
        }
