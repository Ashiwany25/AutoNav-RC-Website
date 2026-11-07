"""Fail-closed validation of future ESP32 sensor telemetry.

This module does not infer position or activate motors. It is a pure data
boundary for incoming hardware readings; measured calibration and on-device
fail-safes remain mandatory.
"""
from dataclasses import dataclass
import json
import math
import time

MAX_MESSAGE_BYTES = 512
MAX_SENSOR_AGE = 0.5


@dataclass(frozen=True)
class Telemetry:
    sequence: int
    encoder_left: int
    encoder_right: int
    front_mm: int
    battery_mv: int
    estop_closed: bool
    received_at: float

    def is_fresh(self, *, now=None, max_age=MAX_SENSOR_AGE):
        if now is None:
            now = time.monotonic()
        return (math.isfinite(now) and 0 <= now - self.received_at <= max_age)

    def safe_to_move(self, *, now=None, minimum_clearance_mm=300):
        return (self.estop_closed and self.is_fresh(now=now)
                and self.front_mm >= minimum_clearance_mm)


class TelemetryDecoder:
    """Strict decoder for newline-delimited ASCII JSON status packets.

    Example: {"type":"SENSOR","seq":1,"enc_l":0,"enc_r":0,
              "front_mm":600,"battery_mv":7400,"estop_closed":true}
    Does NOT guarantee that a real sensor is accurate or connected.
    """

    FIELDS = {"type", "seq", "enc_l", "enc_r", "front_mm", "battery_mv", "estop_closed"}

    def __init__(self, *, clock=time.monotonic):
        self.clock = clock
        self.last_sequence = 0

    def decode(self, data: bytes) -> Telemetry:
        if not isinstance(data, bytes) or not 0 < len(data) <= MAX_MESSAGE_BYTES:
            raise ValueError("Invalid telemetry size")
        try:
            content = data.decode("ascii")
            obj = json.loads(content)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("Malformed telemetry") from exc
        if not isinstance(obj, dict) or set(obj) != self.FIELDS or obj["type"] != "SENSOR":
            raise ValueError("Invalid telemetry fields")
        for field in ("seq", "enc_l", "enc_r", "front_mm", "battery_mv"):
            if type(obj[field]) is not int:
                raise ValueError(f"{field} must be an integer")
        if type(obj["estop_closed"]) is not bool:
            raise ValueError("estop_closed must be boolean")
        seq = obj["seq"]
        if seq <= self.last_sequence or seq > 2**32 - 1:
            raise ValueError("Stale or invalid telemetry sequence")
        if not (-2**31 <= obj["enc_l"] <= 2**31 - 1 and
                -2**31 <= obj["enc_r"] <= 2**31 - 1):
            raise ValueError("Encoder count outside range")
        if not (0 <= obj["front_mm"] <= 10000):
            raise ValueError("Distance outside valid range")
        if not (0 <= obj["battery_mv"] <= 30000):
            raise ValueError("Voltage outside valid range")
        timestamp = self.clock()
        if not math.isfinite(timestamp):
            raise ValueError("Invalid monotonic clock")
        packet = Telemetry(seq, obj["enc_l"], obj["enc_r"], obj["front_mm"],
                           obj["battery_mv"], obj["estop_closed"], timestamp)
        self.last_sequence = seq
        return packet
