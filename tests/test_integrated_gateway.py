import unittest
from hardware.simulated_gateway import SimulatedMotorGateway

class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.now = 10.0
        self.g = SimulatedMotorGateway(clock=lambda: self.now)

    def test_disarmed_cannot_move(self):
        with self.assertRaises(PermissionError):
            self.g.drive(left=40, right=40, telemetry_safe=True)
        self.assertEqual(self.g.state(), (0,0))

    def test_estop_open_rejects_arm(self):
        with self.assertRaises(PermissionError):
            self.g.arm(operator_confirmed=True, sensors_ready=True)

    def test_valid_arming_and_drive(self):
        self.g.enable_estop_loop_for_test()
        self.g.arm(operator_confirmed=True, sensors_ready=True)
        self.g.drive(left=20, right=30, telemetry_safe=True)
        self.assertEqual(self.g.state(), (20,30))

    def test_stop_keeps_stopped(self):
        self.g.enable_estop_loop_for_test()
        self.g.arm(operator_confirmed=True, sensors_ready=True)
        self.g.drive(left=20, right=30, telemetry_safe=True)
        self.g.stop()
        self.assertEqual(self.g.state(), (0,0))
        with self.assertRaises(PermissionError):
            self.g.drive(left=20, right=30, telemetry_safe=True)

    def test_timeout_halts(self):
        self.g.enable_estop_loop_for_test()
        self.g.arm(operator_confirmed=True, sensors_ready=True)
        self.g.drive(left=20, right=30, telemetry_safe=True)
        self.now += .3
        self.assertEqual(self.g.state(), (0,0))
        with self.assertRaises(PermissionError):
            self.g.drive(left=20, right=30, telemetry_safe=True)

    def test_unsafe_telemetry_halts(self):
        self.g.enable_estop_loop_for_test()
        self.g.arm(operator_confirmed=True, sensors_ready=True)
        with self.assertRaises(PermissionError):
            self.g.drive(left=10, right=10, telemetry_safe=False)
        self.assertEqual(self.g.state(), (0,0))
