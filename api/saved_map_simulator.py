
import asyncio
import hashlib
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from fastapi import Request
from api.teach_routes import MAP_PATH
from mapping.teach_mode import TeachModeMapper
from navigation.safety_controller import SafetyController


class Destination(BaseModel):
    row: int = Field(ge=0)
    col: int = Field(ge=0)


class StartRequest(BaseModel):
    goal: Destination


class ObstacleRequest(BaseModel):
    row: int = Field(ge=0)
    col: int = Field(ge=0)
    occupied: bool = True


class SavedMapSimulator:
    def __init__(
        self,
        map_path=MAP_PATH,
        interval=0.5,
        heartbeat_timeout=3.0,
    ):
        if interval <= 0 or heartbeat_timeout <= 0:
            raise ValueError(
                "Interval and heartbeat timeout "
                "must be positive."
            )

        self.map_path = Path(map_path)
        self.interval = interval
        self.heartbeat_timeout = heartbeat_timeout
        import os
        self.dedicated_heartbeat = (
            os.getenv("AUTONAV_DEDICATED_HEARTBEAT", "0") == "1"
        )

        # A shorter deadline for dedicated controller
        # heartbeats. Keep the original timeout for
        # compatibility mode.
        if self.dedicated_heartbeat:
            self.heartbeat_timeout = min(
                self.heartbeat_timeout, 1.5
            )

        self.lock = asyncio.Lock()

        self.position = None
        self.goal = None
        self.path = []

        self.state = "IDLE"
        self.current_step = 0
        self.total_steps = 0

        self.map_fingerprint = None
        self.generation = 0
        self.task = None
        self.heartbeat_deadline = 0.0
        self.owner_id = None

        # Newly detected simulated obstacles.
        # Never modify the saved Teach Mode file.
        self.dynamic_obstacles = set()

        self.replan_count = 0

    def read_map(self):
        if not self.map_path.is_file():
            raise HTTPException(
                status_code=404,
                detail="Save a Teach Mode map first.",
            )

        try:
            content = self.map_path.read_bytes()
            fingerprint = hashlib.sha256(
                content
            ).hexdigest()

            mapper = TeachModeMapper.load(
                self.map_path
            )

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

        return mapper, fingerprint

    def effective_grid(self, mapper):
        grid = [
            row.copy()
            for row in mapper.grid
        ]

        for row, col in self.dynamic_obstacles:
            if (
                0 <= row < mapper.height
                and 0 <= col < mapper.width
            ):
                grid[row][col] = 1

        return grid

    def make_controller(self, mapper):
        return SafetyController(
            self.effective_grid(mapper),
            clearance=1,
        )

    def renew_heartbeat_locked(self):
        if self.state == "NAVIGATING":
            self.heartbeat_deadline = (
                time.monotonic()
                + self.heartbeat_timeout
            )

    def check_heartbeat_locked(self):
        if self.state != "NAVIGATING":
            return False

        if time.monotonic() < self.heartbeat_deadline:
            return False

        self.generation += 1
        self.state = "CONNECTION_LOST"
        self.path = []
        self.heartbeat_deadline = 0.0

        task = self.task
        self.task = None

        if task is not None and not task.done():
            task.cancel()

        return True

    def block_locked(self):
        self.generation += 1
        self.state = "BLOCKED"
        self.path = []
        self.heartbeat_deadline = 0.0

        task = self.task
        self.task = None

        if task is not None and not task.done():
            task.cancel()

    def status_payload(self):
        remaining_ms = 0

        if self.state == "NAVIGATING":
            remaining_ms = max(
                0,
                int(
                    (
                        self.heartbeat_deadline
                        - time.monotonic()
                    ) * 1000
                ),
            )

        return {
            "success": True,
            "simulation": True,
            "physical_motors_active": False,
            "navigation_state": self.state,
            "position": (
                {
                    "row": self.position[0],
                    "col": self.position[1],
                }
                if self.position is not None
                else None
            ),
            "goal": (
                {
                    "row": self.goal[0],
                    "col": self.goal[1],
                }
                if self.goal is not None
                else None
            ),
            "path": [
                {"row": row, "col": col}
                for row, col in self.path
            ],
            "current_step": self.current_step,
            "total_steps": self.total_steps,
            "remaining_steps": max(
                0,
                len(self.path) - 1,
            ),
            "heartbeat_timeout_ms": int(
                self.heartbeat_timeout * 1000
            ),
            "heartbeat_remaining_ms": remaining_ms,
            "communication_lost": (
                self.state == "CONNECTION_LOST"
            ),
            "dynamic_obstacles": [
                {"row": row, "col": col}
                for row, col in sorted(
                    self.dynamic_obstacles
                )
            ],
            "dynamic_obstacle_count": len(
                self.dynamic_obstacles
            ),
            "replan_count": self.replan_count,
        }

    def require_owner_locked(self, controller_id):
        if (
            self.state == "NAVIGATING"
            and self.owner_id is not None
            and controller_id != self.owner_id
        ):
            raise HTTPException(
                status_code=403,
                detail="Navigation belongs to another controller.",
            )

    async def start(self, goal, controller_id=None):
        async with self.lock:
            self.require_owner_locked(controller_id)
            mapper, fingerprint = self.read_map()

            if (
                self.position is None
                or fingerprint != self.map_fingerprint
            ):
                if mapper.robot_position is None:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "Saved map has no robot position."
                        ),
                    )

                start = tuple(mapper.robot_position)

                # Obstacles belong to the previous map.
                if (
                    self.map_fingerprint is not None
                    and fingerprint != self.map_fingerprint
                ):
                    self.dynamic_obstacles.clear()
            else:
                start = self.position

            controller = self.make_controller(
                mapper
            )

            if not controller.is_safe(start):
                raise HTTPException(
                    status_code=409,
                    detail="Robot starting position is unsafe.",
                )

            if not controller.is_safe(goal):
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "Destination is unknown, occupied, "
                        "or violates obstacle clearance."
                    ),
                )

            route = controller.plan_route(
                start,
                goal,
            )

            if route is None:
                raise HTTPException(
                    status_code=409,
                    detail="No safe route to destination.",
                )

            old_task = self.task

            self.generation += 1
            generation = self.generation

            if old_task is not None and not old_task.done():
                old_task.cancel()

            self.owner_id = controller_id
            self.map_fingerprint = fingerprint
            self.position = start
            self.goal = goal
            self.path = list(route)

            self.current_step = 0
            self.total_steps = len(route) - 1
            self.replan_count = 0

            if start == goal:
                self.state = "ARRIVED"
                self.heartbeat_deadline = 0.0
                self.task = None
            else:
                self.state = "NAVIGATING"
                self.renew_heartbeat_locked()

                self.task = asyncio.create_task(
                    self.execute(generation)
                )

            return self.status_payload()

    async def update_obstacle(
        self,
        row,
        col,
        occupied=True,
    ):
        async with self.lock:
            mapper, fingerprint = self.read_map()

            if not (
                0 <= row < mapper.height
                and 0 <= col < mapper.width
            ):
                raise HTTPException(
                    status_code=400,
                    detail="Obstacle is outside the map.",
                )

            # A temporary obstacle cannot erase a
            # wall or reveal an unknown saved cell.
            if mapper.grid[row][col] != 0:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "Dynamic obstacles can only "
                        "be edited on saved free cells."
                    ),
                )

            if (
                self.state == "NAVIGATING"
                and fingerprint != self.map_fingerprint
            ):
                self.block_locked()

                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Saved map changed. "
                        "Navigation was stopped."
                    ),
                )

            changed = False

            if occupied:
                if (row, col) not in self.dynamic_obstacles:
                    self.dynamic_obstacles.add((row, col))
                    changed = True
            else:
                if (row, col) in self.dynamic_obstacles:
                    self.dynamic_obstacles.remove((row, col))
                    changed = True

            replanned = False

            if changed and self.state == "NAVIGATING":
                if self.check_heartbeat_locked():
                    return {
                        **self.status_payload(),
                        "replanned": False,
                        "message": (
                            "Communication timeout. "
                            "Simulation stopped."
                        ),
                    }

                controller = self.make_controller(
                    mapper
                )

                # Cannot continue if the new obstacle
                # violates clearance at the current pose.
                if not controller.is_safe(
                    self.position
                ):
                    self.block_locked()

                elif not controller.is_safe(self.goal):
                    self.block_locked()

                else:
                    new_path = controller.plan_route(
                        self.position,
                        self.goal,
                    )

                    if new_path is None:
                        self.block_locked()
                    else:
                        self.path = list(new_path)
                        self.replan_count += 1
                        replanned = True

                        # Keep original completed-step
                        # progress while updating the
                        # remaining route length.
                        self.total_steps = (
                            self.current_step
                            + len(new_path) - 1
                        )

            return {
                **self.status_payload(),
                "replanned": replanned,
                "obstacle_changed": changed,
                "message": (
                    "Safe route recalculated."
                    if replanned
                    else "Obstacle map updated."
                ),
            }

    async def execute(self, generation):
        try:
            while True:
                await asyncio.sleep(self.interval)

                async with self.lock:
                    if (
                        generation != self.generation
                        or self.state != "NAVIGATING"
                    ):
                        return

                    if self.check_heartbeat_locked():
                        return

                    try:
                        mapper, fingerprint = self.read_map()

                        if fingerprint != self.map_fingerprint:
                            self.block_locked()
                            return

                        controller = self.make_controller(
                            mapper
                        )

                        if (
                            not controller.is_safe(self.position)
                            or len(self.path) < 2
                        ):
                            self.block_locked()
                            return

                        next_position = self.path[1]

                        if not controller.is_safe(
                            next_position
                        ):
                            self.block_locked()
                            return

                        self.position = next_position
                        self.path = self.path[1:]
                        self.current_step += 1

                        if self.position == self.goal:
                            self.state = "ARRIVED"
                            self.path = [self.position]
                            self.heartbeat_deadline = 0.0
                            return

                    except HTTPException:
                        self.block_locked()
                        return

        except asyncio.CancelledError:
            return

    async def stop(self):
        async with self.lock:
            self.generation += 1

            task = self.task
            self.task = None

            if task is not None and not task.done():
                task.cancel()

            self.state = "STOPPED"
            self.path = []
            self.goal = None
            self.heartbeat_deadline = 0.0

            result = self.status_payload()

        if task is not None and not task.done():
            await asyncio.gather(
                task,
                return_exceptions=True,
            )

        return result

    async def status(self):
        async with self.lock:
            expired = self.check_heartbeat_locked()

            # Compatibility only: the existing phone
            # currently renews its lease through status.
            # Dedicated mode disables that behavior.
            if not expired and not self.dedicated_heartbeat:
                self.renew_heartbeat_locked()

            return self.status_payload()

    async def heartbeat(self, controller_id=None):
        async with self.lock:
            self.require_owner_locked(controller_id)
            if self.check_heartbeat_locked():
                raise HTTPException(
                    status_code=409,
                    detail="Navigation heartbeat expired.",
                )

            if self.state != "NAVIGATING":
                raise HTTPException(
                    status_code=409,
                    detail="Navigation is not active.",
                )

            self.renew_heartbeat_locked()
            return self.status_payload()



def create_saved_map_simulator_router(
    map_path=MAP_PATH,
    interval=0.5,
    heartbeat_timeout=3.0,
):
    simulator = SavedMapSimulator(
        map_path=map_path,
        interval=interval,
        heartbeat_timeout=heartbeat_timeout,
    )

    router = APIRouter(
        prefix="/api/v1/teach/navigation/sim",
        tags=["Saved Map Simulation"],
    )

    @router.post("/start")
    async def start_simulation(
        request: StartRequest,
        http_request: Request,
    ):
        return await simulator.start(
            (
                request.goal.row,
                request.goal.col,
            ),
            controller_id=getattr(
                http_request.state, "controller_id", None
            ),
        )

    @router.get("/status")
    async def simulation_status():
        return await simulator.status()

    @router.post("/heartbeat")
    async def simulation_heartbeat(
        http_request: Request,
    ):
        return await simulator.heartbeat(
            controller_id=getattr(
                http_request.state, "controller_id", None
            ),
        )

    @router.post("/stop")
    async def stop_simulation():
        return await simulator.stop()

    @router.post("/obstacle")
    async def update_dynamic_obstacle(
        request: ObstacleRequest,
    ):
        return await simulator.update_obstacle(
            request.row,
            request.col,
            request.occupied,
        )

    return router
