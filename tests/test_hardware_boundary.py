import unittest
from hardware.serial_protocol import Drive, MotorSerialController, FirmwareWatchdogModel


class FakePort:
    def __init__(self): self.sent = []
    def write(self, data): self.sent.append(data); return len(data)


class HardwareBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.port = FakePort()
        self.host = MotorSerialController(self.port, clock=lambda: self.now)
        self.device = FirmwareWatchdogModel(clock=lambda: self.now)

    def relay(self):
        for msg in self.port.sent:
            self.device.receive(msg.decode().rstrip('\n'))
        self.port.sent.clear()

    def test_default_disarmed_estop_open(self):
        with self.assertRaises(PermissionError): self.host.drive(Drive(1, 20, 20))
        with self.assertRaises(PermissionError): self.host.arm(operator_confirmed=False, sensors_ready=True)
        self.assertEqual((self.device.left, self.device.right), (0, 0))

    def test_arm_and_watchdog_expiry(self):
        self.device.set_estop(circuit_closed=True)
        self.host.arm(operator_confirmed=True, sensors_ready=True)
        self.relay()
        self.host.drive(Drive(1, 40, -20))
        self.relay()
        self.assertEqual((self.device.left, self.device.right), (40, -20))
        self.now += .251
        self.device.tick()
        self.assertEqual((self.device.left, self.device.right), (0, 0))
        self.assertIsNone(self.device.nonce)

    def test_estop_blocks_and_disarms(self):
        self.device.set_estop(circuit_closed=True)
        self.host.arm(operator_confirmed=True, sensors_ready=True); self.relay()
        self.host.drive(Drive(1, 40, 40)); self.relay()
        self.device.set_estop(circuit_closed=False)
        self.assertEqual((self.device.left, self.device.right), (0, 0))
        self.assertFalse(self.device.receive('DRV deadbeefdeadbeef 2 50 50'))

    def test_duplicate_rejected_host(self):
        self.device.set_estop(circuit_closed=True)
        self.host.arm(operator_confirmed=True, sensors_ready=True)
        self.host.drive(Drive(1, 10, 10))
        with self.assertRaises(ValueError): self.host.drive(Drive(1, 10, 10))

    def test_old_session_packet_rejected(self):
        self.device.set_estop(circuit_closed=True)
        old = self.host.arm(operator_confirmed=True, sensors_ready=True); self.relay()
        new = self.host.arm(operator_confirmed=True, sensors_ready=True); self.relay()
        self.assertNotEqual(old, new)
        self.assertFalse(self.device.receive(f'DRV {old} 1 50 50'))
        self.assertEqual(self.device.left, 0)

    def test_stop_always_sent_even_disarmed(self):
        self.host.stop();self.assertEqual(self.port.sent[-1],b'STOP\n')

    def test_invalid_drive_rejected(self):
        for args in ((1, 101, 0),(0, 5, 5),(1, 0.5, 0)):
            with self.assertRaises(ValueError): Drive(*args)

    def test_firmware_rejects_malformed(self):
        self.device.set_estop(circuit_closed=True)
        self.assertFalse(self.device.receive('DRV bad 1 90 90'))
        self.assertFalse(self.device.receive('ARM garbage'))
        self.assertEqual(self.device.left, 0)

    def test_watchdog_cannot_be_disabled(self):
        with self.assertRaises(ValueError): FirmwareWatchdogModel(timeout_seconds=2)

if __name__ == '__main__':unittest.main()
