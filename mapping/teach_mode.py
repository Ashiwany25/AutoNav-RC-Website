
import json
import os
import tempfile

from pathlib import Path


UNKNOWN = -1
FREE = 0
OCCUPIED = 1


class TeachModeMapper:
    """
    Grid-based indoor mapping engine.

    Supports observations from a simulator
    or a future real sensor adapter.

    UNKNOWN  = -1
    FREE     = 0
    OCCUPIED = 1
    """

    def __init__(
        self,
        width=15,
        height=15,
        resolution=0.10,
    ):
        if width <= 0 or height <= 0:
            raise ValueError(
                "Map dimensions must be positive."
            )

        if resolution <= 0:
            raise ValueError(
                "Resolution must be positive."
            )

        self.width = width
        self.height = height
        self.resolution = resolution

        self.grid = [
            [UNKNOWN] * width
            for _ in range(height)
        ]

        self.robot_position = None
        self.observation_count = 0

    def in_bounds(self, row, col):
        return (
            0 <= row < self.height
            and 0 <= col < self.width
        )

    def update_cell(self, row, col, value):
        if not self.in_bounds(row, col):
            raise ValueError(
                "Observation outside map boundaries."
            )

        if value not in (FREE, OCCUPIED):
            raise ValueError(
                "Observation must be FREE or OCCUPIED."
            )

        self.grid[row][col] = value
        self.observation_count += 1

    def update_robot_position(self, row, col):
        if not self.in_bounds(row, col):
            raise ValueError(
                "Robot position outside map."
            )

        self.robot_position = (row, col)

    def add_observations(self, observations):
        """
        Accept observations as:

        [
            {"row": 2, "col": 3, "value": 0},
            {"row": 2, "col": 4, "value": 1}
        ]

        Validate the entire batch before applying.
        """
        validated = []

        for observation in observations:
            row = observation["row"]
            col = observation["col"]
            value = observation["value"]

            if not self.in_bounds(row, col):
                raise ValueError(
                    "Observation outside map."
                )

            if value not in (FREE, OCCUPIED):
                raise ValueError(
                    "Invalid occupancy value."
                )

            validated.append((row, col, value))

        for row, col, value in validated:
            self.update_cell(row, col, value)

    def exploration_percentage(self):
        explored = sum(
            cell != UNKNOWN
            for row in self.grid
            for cell in row
        )

        return round(
            100 * explored
            / (self.width * self.height),
            2,
        )

    def to_dict(self):
        return {
            "map_type": "occupancy_grid",
            "mode": "TEACH",
            "width": self.width,
            "height": self.height,
            "resolution": self.resolution,
            "resolution_unit": "meters_per_cell",
            "grid": [
                row.copy()
                for row in self.grid
            ],
            "robot_position": (
                {
                    "row": self.robot_position[0],
                    "col": self.robot_position[1],
                }
                if self.robot_position is not None
                else None
            ),
            "observation_count": (
                self.observation_count
            ),
            "exploration_percentage": (
                self.exploration_percentage()
            ),
            "legend": {
                "-1": "unknown",
                "0": "free",
                "1": "occupied",
            },
        }

    def save(self, filepath):
        """
        Atomically save the current map as JSON.
        """
        path = Path(filepath)
        path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        temp_name = None

        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                suffix=".tmp",
                delete=False,
            ) as temporary_file:
                temp_name = temporary_file.name

                json.dump(
                    self.to_dict(),
                    temporary_file,
                    indent=2,
                )

                temporary_file.flush()
                os.fsync(
                    temporary_file.fileno()
                )

            os.replace(temp_name, path)

        finally:
            if (
                temp_name is not None
                and os.path.exists(temp_name)
            ):
                os.unlink(temp_name)

        return str(path)

    @classmethod
    def load(cls, filepath):
        path = Path(filepath)

        with path.open(
            "r",
            encoding="utf-8",
        ) as file:
            data = json.load(file)

        mapper = cls(
            width=data["width"],
            height=data["height"],
            resolution=data["resolution"],
        )

        grid = data["grid"]

        if (
            len(grid) != mapper.height
            or any(
                len(row) != mapper.width
                for row in grid
            )
        ):
            raise ValueError(
                "Saved grid dimensions are invalid."
            )

        if any(
            type(cell) is not int
            or cell not in (
                UNKNOWN,
                FREE,
                OCCUPIED,
            )
            for row in grid
            for cell in row
        ):
            raise ValueError(
                "Saved grid contains invalid values."
            )

        mapper.grid = [
            row.copy()
            for row in grid
        ]

        position = data.get("robot_position")

        if position is not None:
            mapper.update_robot_position(
                position["row"],
                position["col"],
            )

        mapper.observation_count = data.get(
            "observation_count",
            0,
        )

        return mapper
