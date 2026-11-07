import json
import unittest
from hardware.sensor_telemetry import TelemetryDecoder


class SensorTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.decoder = TelemetryDecoder(clock=lambda: self.now)
        self.payload = {"type": "SENSOR", "seq": 1, "enc_l": 0, "enc_r": 0,
                        "front_mm": 600, "battery_mv": 7400, "estop_closed": True}

    def packet(self, **changes):
        return json.dumps({**self.payload, **changes}).encode("ascii")

    def test_valid_safe_packet(self):
        pkt = self.decoder.decode(self.packet())
        self.assertTrue(pkt.safe_to_move(now=self.now))

    def test_obstacle_prevents_movement(self):
        self.assertFalse(self.decoder.decode(self.packet(front_mm=200)).safe_to_move(now=self.now))

    def test_estop_prevents_movement(self):
        self.assertFalse(self.decoder.decode(self.packet(estop_closed=False)).safe_to_move(now=self.now))

    def test_expired_data_prevents_movement(self):
        pkt = self.decoder.decode(self.packet())
        self.assertFalse(pkt.safe_to_move(now=self.now + .501))

    def test_stale_sequence_rejected(self):
        self.decoder.decode(self.packet())
        with self.assertRaises(ValueError):
            self.decoder.decode(self.packet())

    def test_invalid_distance_rejected(self):
        with self.assertRaises(ValueError):
            self.decoder.decode(self.packet(front_mm=-1))

    def test_invalid_boolean_rejected(self):
        with self.assertRaises(ValueError):
            self.decoder.decode(self.packet(estop_closed=1))

    def test_extra_fields_rejected(self):
        with self.assertRaises(ValueError):
            self.decoder.decode(self.packet(secret="bad"))

    def test_missing_fields_rejected(self):
        raw = self.payload.copy(); raw.pop("enc_l")
        with self.assertRaises(ValueError):
            self.decoder.decode(json.dumps(raw).encode())

    def test_bad_encoding_and_oversize_rejected(self):
        for raw in (b"\xff", b"x" * 513):
            with self.assertRaises(ValueError):
                self.decoder.decode(raw)

    def test_encoder_wrong_type_rejected(self):
        with self.assertRaises(ValueError):
            self.decoder.decode(self.packet(enc_l=True))


if __name__ == "__main__":
    unittest.main()
