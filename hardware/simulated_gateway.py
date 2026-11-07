"""Never connects to motors. Exercises controller ownership, command and watchdog models.

A future real serial adapter must implement independent firmware-side safeguards.
"""
from hardware.serial_protocol import MotorSerialController, Drive, FirmwareWatchdogModel


class MemoryPort:
    def __init__(self):
        self.lines = []

    def write(self, data):
        self.lines.append(data.decode('ascii').strip())
        return len(data)


class SimulatedMotorGateway:
    def __init__(self, *, clock):
        self.clock = clock
        self.port = MemoryPort()
        self.host = MotorSerialController(self.port, clock=clock)
        self.firmware = FirmwareWatchdogModel(clock=clock)
        self._next_seq = 0

    def enable_estop_loop_for_test(self):
        self.firmware.set_estop(circuit_closed=True)

    def _deliver(self):
        while self.port.lines:
            command = self.port.lines.pop(0)
            if not self.firmware.receive(command):
                self.host.stop()
                self.firmware.receive('STOP')
                self.port.lines.clear()
                raise PermissionError('Firmware rejected command')

    def arm(self, *, operator_confirmed, sensors_ready):
        self.host.arm(operator_confirmed=operator_confirmed, sensors_ready=sensors_ready)
        self._deliver()
        self._next_seq = 0

    def drive(self, *, left, right, telemetry_safe):
        self.firmware.tick()
        if not telemetry_safe or self.firmware.nonce is None:
            self.stop()
            raise PermissionError('Movement requires fresh safe telemetry and active session')
        self._next_seq += 1
        self.host.drive(Drive(self._next_seq, left, right))
        self._deliver()

    def stop(self):
        self.host.stop()
        self._deliver()

    def state(self):
        self.firmware.tick()
        return (self.firmware.left, self.firmware.right)
