
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from api.teach_routes import MAP_PATH
from mapping.teach_mode import TeachModeMapper
from navigation.safety_controller import SafetyController


class GridPosition(BaseModel):
    row: int = Field(ge=0)
    col: int = Field(ge=0)


class SavedRouteRequest(BaseModel):
    goal: GridPosition


def create_teach_navigation_router(
    save_path=MAP_PATH,
):
    router = APIRouter(
        prefix="/api/v1/teach/navigation",
        tags=["Teach Map Navigation"],
    )

    save_path = Path(save_path)

    @router.post("/plan")
    async def plan_saved_map_route(
        request: SavedRouteRequest,
    ):
        """
        Plan a route on a saved Teach Mode map.

        This endpoint does not move the robot.

        Map values:
          -1 = unknown, blocked
           0 = free
           1 = occupied, blocked

        A one-cell safety clearance is preserved.
        """

        if not save_path.is_file():
            raise HTTPException(
                status_code=404,
                detail=(
                    "No saved Teach Mode map found. "
                    "Finish and save a map first."
                ),
            )

        try:
            mapper = TeachModeMapper.load(
                save_path
            )
        except (
            ValueError,
            KeyError,
            TypeError,
            OSError,
        ) as error:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Saved Teach Mode map is invalid: "
                    f"{error}"
                ),
            ) from error

        if mapper.robot_position is None:
            raise HTTPException(
                status_code=409,
                detail=(
                    "The saved map has no robot "
                    "starting position."
                ),
            )

        start = tuple(
            mapper.robot_position
        )

        goal = (
            request.goal.row,
            request.goal.col,
        )

        controller = SafetyController(
            mapper.grid,
            clearance=1,
        )

        if not controller.is_safe(start):
            raise HTTPException(
                status_code=409,
                detail=(
                    "The saved robot position is "
                    "not safe in the explored map. "
                    "Explore more free cells."
                ),
            )

        if not controller.is_safe(goal):
            raise HTTPException(
                status_code=400,
                detail=(
                    "Destination is unknown, occupied, "
                    "outside the map, or too close "
                    "to an obstacle or boundary."
                ),
            )

        path = controller.plan_route(
            start,
            goal,
        )

        if path is None:
            raise HTTPException(
                status_code=409,
                detail=(
                    "No safe route exists through "
                    "the explored free cells."
                ),
            )

        safe_path = [
            {
                "row": row,
                "col": col,
            }
            for row, col in path
        ]

        return {
            "success": True,
            "simulation": True,
            "map_source": "saved_teach_mode",
            "execution_started": False,
            "clearance_cells": 1,
            "start": {
                "row": start[0],
                "col": start[1],
            },
            "goal": request.goal.model_dump(),
            "path": safe_path,
            "steps": len(safe_path) - 1,
            "navigation_state": "READY",
            "map_width": mapper.width,
            "map_height": mapper.height,
            "exploration_percentage": (
                mapper.exploration_percentage()
            ),
            "message": (
                "Safe route planned on the "
                "saved Teach Mode map. "
                "Robot movement has not started."
            ),
        }

    return router
