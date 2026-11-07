"""Testable, fail-closed serial motor protocol for FUTURE ESP32 integration.

This module does not connect to a motor, implement localization, or claim
physical safety. The wire transport remains an injected object; pairing and
HTTP auth are handled by the existing FastAPI layer.

Each controller session chooses a new random 64-bit hex nonce. The ESP32 must
receive ARM with that nonce before any nonzero command and fails safe on
watchdog expiry, E-STOP input or malformed commands. The host must never
assume an ACK means physical movement occurred.
"""
from dataclasses import dataclass
import re
import secrets
import time
from typing import Protocol

_NONCE = re.compile(r"^[0-9a-f]{16}$")


class WritePort(Protocol):
    def write(self, data: bytes) -> int: ...


@dataclass(frozen=True)
class Drive:
    sequence: int
    left: int
    right: int

    def __post_init__(self):
        if type(self.sequence) is not int or self.sequence < 1:
            raise ValueError("Sequence must be a positive integer")
        if any(type(v) is not int or abs(v) > 100 for v in (self.left, self.right)):
            raise ValueError("Drive values must be integer percentages between -100 and 100")


class MotorSerialController:
    """Host-side session and packet sequencing. Not a hardware safety watchdog."""
    def __init__(self, port: WritePort, *, clock=time.monotonic):
        self._port = port
        self._clock = clock
        self._nonce = None
        self._sequence = 0
        self._last_drive = None

    @property
    def armed(self) -> bool:
        return self._nonce is not None

    def _write(self, line: str) -> None:
        data = (line + "\n").encode("ascii")
        written = self._port.write(data)
        if written != len(data):
            self._nonce = None
            self._last_drive = None
            raise OSError("Serial command write incomplete; control disabled")

    def arm(self, *, operator_confirmed: bool, sensors_ready: bool) -> str:
        if not (operator_confirmed and sensors_ready):
            raise PermissionError("Explicit operator confirmation and sensor readiness required")
        self._nonce = None
        self._sequence = 0
        self._last_drive = None
        nonce = secrets.token_hex(8)
        assert _NONCE.fullmatch(nonce)
        self._write(f"ARM {nonce}")
        self._nonce = nonce
        return nonce

    def drive(self, cmd: Drive) -> None:
        if self._nonce is None:
            raise PermissionError("Not armed; movement blocked")
        if cmd.sequence <= self._sequence:
            raise ValueError("Stale or duplicate drive sequence")
        self._write(f"DRV {self._nonce} {cmd.sequence} {cmd.left} {cmd.right}")
        self._sequence = cmd.sequence
        self._last_drive = self._clock()

    def stop(self) -> None:
        # Do not require being armed to send STOP.
        # Firmware always accepts STOP regardless of session state.
        self._nonce = None
        self._last_drive = None
        self._write("STOP")

    def close(self) -> None:
        self.stop()


class FirmwareWatchdogModel:
    """Python reference model; firmware has its own independent timer."""
    def __init__(self, *, timeout_seconds=0.25, clock=time.monotonic):
        if timeout_seconds <= 0 or timeout_seconds > 0.5:
            raise ValueError("Watchdog timeout must be within (0, 0.5]s")
        self.timeout_seconds = timeout_seconds
        self.clock = clock
        self.nonce = None
        self.sequence = 0
        self.last_drive = None
        self.left = 0
        self.right = 0
        self.estop_open = True  # Normally-closed switch; default unwired = STOP

    def set_estop(self, *, circuit_closed: bool) -> None:
        self.estop_open = not circuit_closed
        if self.estop_open:
            self._halt()
            self.nonce = None

    def _halt(self) -> None:
        self.left = self.right = 0
        self.last_drive = None

    def tick(self) -> None:
        if self.last_drive is not None and self.clock() - self.last_drive >= self.timeout_seconds:
            self._halt()
            self.nonce = None

    def receive(self, line: str) -> bool:
        self.tick()
        if line == "STOP":
            self._halt()
            self.nonce = None
            return True
        if self.estop_open or not isinstance(line, str) or len(line) > 100:
            self._halt()
            return False
        parts = line.split()
        if len(parts) == 2 and parts[0] == "ARM" and _NONCE.fullmatch(parts[1]):
            self._halt()
            self.nonce = parts[1]
            self.sequence = 0
            return True
        if len(parts) != 5 or parts[0] != "DRV" or self.nonce is None:
            self._halt()
            return False
        try:
            if parts[1] != self.nonce:
                return False
            sequence = int(parts[2]); left = int(parts[3]); right = int(parts[4])
            cmd = Drive(sequence, left, right)
            if cmd.sequence <= self.sequence:
                return False
        except (ValueError, TypeError):
            self._halt()
            return False
        self.sequence = sequence
        self.left, self.right = cmd.left, cmd.right
        self.last_drive = self.clock()
        return True
