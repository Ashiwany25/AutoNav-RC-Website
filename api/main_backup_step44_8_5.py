
import asyncio
import sys
import time

from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


# ==================================================
# PROJECT IMPORTS
# ==================================================

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from navigation.safety_controller import (
    SafetyController,
    NavigationState,
)


# ==================================================
# CONFIGURATION
# ==================================================

API_VERSION = "1.0.0"

MANUAL_TIMEOUT_SECONDS = 0.6
WATCHDOG_CHECK_SECONDS = 0.1


# ==================================================
# SIMULATED INDOOR MAP
# ==================================================

def create_test_map():
    """
    Temporary simulated indoor environment.

    0 = free space
    1 = obstacle
    """

    grid = [[0] * 15 for _ in range(15)]

    for row in range(4, 11):
        grid[row][6] = 1

    for col in range(9, 13):
        grid[9][col] = 1

    return grid


# ==================================================
# API REQUEST / RESPONSE MODELS
# ==================================================

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

    # Optional during Flutter migration.
    sequence: int | None = Field(
        default=None,
        ge=1,
    )


class ManualStopRequest(BaseModel):
    sequence: int | None = Field(
        default=None,
        ge=1,
    )


# ==================================================
# SIMULATION ROBOT
# ==================================================

class SimulationRobot:

    def __init__(self):
        self.grid = create_test_map()

        # Preserve existing obstacle clearance.
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

        # Manual driving state.
        self.manual_direction = "STOPPED"
        self.manual_speed = 0
        self.manual_deadline = 0.0

        # Automatic manual-command watchdog.
        self.watchdog_task = None

        # Highest sequenced command accepted
        # by this server process.
        self.last_manual_sequence = 0

    # ------------------------------------------
    # CLEAR MANUAL COMMAND
    # ------------------------------------------

    def clear_manual_command(self):
        """
        Clear manual driving state.

        Caller must hold self.lock.
        """
        self.manual_direction = "STOPPED"
        self.manual_speed = 0
        self.manual_deadline = 0.0

    # ------------------------------------------
    # STOP ALL SIMULATED MOVEMENT
    # ------------------------------------------

    def stop_all_locked(self):
        """
        Stop the simulated robot.

        Caller must hold self.lock.

        Returns the navigation task so it
        can be awaited outside the lock.
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

    # ------------------------------------------
    # CHECK MANUAL COMMAND SEQUENCE
    # ------------------------------------------

    def check_manual_sequence(self, sequence):
        """
        Reject duplicate or older numbered
        drive commands.

        Caller must hold self.lock.
        """

        if sequence is None:
            # Legacy compatibility only.
            return

        if sequence <= self.last_manual_sequence:
            raise HTTPException(
                status_code=409,
                detail=(
                    "Stale manual command rejected."
                ),
            )

    # ------------------------------------------
    # EXECUTE AUTONOMOUS NAVIGATION
    # ------------------------------------------

    async def execute_navigation(self):
        """
        Move along an A* route in simulation.
        """

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

    # ------------------------------------------
    # MANUAL COMMAND WATCHDOG
    # ------------------------------------------

    async def manual_watchdog(self):
        """
        Automatically stop expired manual
        commands in simulation.
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


# ==================================================
# GLOBAL SIMULATED ROBOT
# ==================================================

robot = SimulationRobot()


# ==================================================
# FASTAPI LIFESPAN
# ==================================================

@asynccontextmanager
async def lifespan(app: FastAPI):

    print("AutoNav API v1 started")

    robot.watchdog_task = asyncio.create_task(
        robot.manual_watchdog()
    )

    try:
        yield

    finally:
        async with robot.lock:
            robot.stop_all_locked()

            tasks = [
                task
                for task in [
                    robot.task,
                    robot.watchdog_task,
                ]
                if (
                    task is not None
                    and not task.done()
                )
            ]

            for task in tasks:
                task.cancel()

        if tasks:
            await asyncio.gather(
                *tasks,
                return_exceptions=True,
            )

        print("AutoNav API v1 stopped")


# ==================================================
# FASTAPI APPLICATION
# ==================================================

app = FastAPI(
    title="AutoNav API",
    description=(
        "Local API for AutoNav RC simulation."
    ),
    version=API_VERSION,
    lifespan=lifespan,
)


# ==================================================
# 1. HEALTH
# ==================================================

@app.get("/api/v1/health")
async def health():

    return {
        "success": True,
        "service": "AutoNav API",
        "version": API_VERSION,
        "status": "online",
        "simulation": True,
        "timestamp": datetime.now(
            timezone.utc
        ).isoformat(),
    }


# ==================================================
# 2. ROBOT STATUS
# ==================================================

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


# ==================================================
# 3. NAVIGATION PLAN
# ==================================================

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


# ==================================================
# 4. NAVIGATION START
# ==================================================

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
                detail=(
                    "Robot is already navigating."
                ),
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


# ==================================================
# 5. NAVIGATION STOP
# ==================================================

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


# ==================================================
# 6. NAVIGATION STATUS
# ==================================================

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
                max(
                    0,
                    len(robot.path) - 1,
                )
                if robot.path else 0
            ),
        }


# ==================================================
# 7. CURRENT INDOOR MAP
# ==================================================

@app.get("/api/v1/maps/current")
async def get_current_map():
    """
    Return current simulated occupancy map.
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


# ==================================================
# 8. MANUAL DRIVE
# ==================================================

@app.post("/api/v1/manual/drive")
async def manual_drive(
    request: ManualDriveRequest,
):
    """
    Accept a simulated manual drive command.

    A numbered command must be newer than
    the last accepted numbered command.

    Legacy unnumbered commands remain allowed
    temporarily during the Flutter migration.
    """

    async with robot.lock:

        # --------------------------------------
        # MANUAL / AUTONOMOUS MODE INTERLOCK
        # --------------------------------------

        if robot.mode == "NAVIGATING":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Autonomous navigation is "
                    "active. Stop navigation first."
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

        # --------------------------------------
        # REJECT STALE NUMBERED COMMANDS
        # --------------------------------------

        robot.check_manual_sequence(
            request.sequence
        )

        # --------------------------------------
        # ACCEPT NEW NUMBERED COMMAND
        # --------------------------------------

        if request.sequence is not None:
            robot.last_manual_sequence = (
                request.sequence
            )

        # --------------------------------------
        # UPDATE SIMULATED MANUAL STATE
        # --------------------------------------

        robot.mode = "MANUAL"

        robot.controller.stop()

        robot.path = []
        robot.goal = None

        robot.manual_direction = (
            request.direction
        )

        robot.manual_speed = (
            request.speed
        )

        robot.manual_deadline = (
            time.monotonic()
            + MANUAL_TIMEOUT_SECONDS
        )

        return {
            "success": True,
            "simulation": True,
            "mode": robot.mode,
            "direction": (
                robot.manual_direction
            ),
            "speed": robot.manual_speed,
            "sequence": request.sequence,
            "last_sequence": (
                robot.last_manual_sequence
            ),
            "timeout_ms": int(
                MANUAL_TIMEOUT_SECONDS * 1000
            ),
            "message": (
                "Simulated manual command accepted."
            ),
        }


# ==================================================
# 9. MANUAL STOP
# ==================================================

@app.post("/api/v1/manual/stop")
async def manual_stop(
    request: ManualStopRequest | None = None,
):
    """
    Stop simulated movement in any mode.

    Duplicate or older STOP requests are
    accepted because STOP must remain
    idempotent.

    A newer STOP sequence advances the
    stale-command protection watermark.
    """

    async with robot.lock:

        if (
            request is not None
            and request.sequence is not None
        ):
            robot.last_manual_sequence = max(
                robot.last_manual_sequence,
                request.sequence,
            )

        task = robot.stop_all_locked()

        last_sequence = (
            robot.last_manual_sequence
        )

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
        "last_sequence": last_sequence,
        "message": (
            "Simulated robot stopped."
        ),
    }


# ==================================================
# 10. MANUAL STATUS
# ==================================================

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
            "direction": (
                robot.manual_direction
            ),
            "speed": robot.manual_speed,
            "command_remaining_ms": (
                remaining_ms
            ),
            "last_sequence": (
                robot.last_manual_sequence
            ),
            "position": {
                "row": robot.position[0],
                "col": robot.position[1],
            },
        }
