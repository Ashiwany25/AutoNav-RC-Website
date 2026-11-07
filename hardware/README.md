# AutoNav RC — Hardware boundary (prototype)

This directory is **not a complete physical RC car controller**. It is a
simulation-tested, hardware-facing command protocol and ESP32 firmware scaffold.

## Design constraints

- The existing FastAPI simulator stays unchanged: it never activates motors.
- A **separately authorized and supervised** hardware session is required to
  send commands to the future ESP32. Do not expose serial commands directly as
  unauthenticated HTTP routes.
- A normally closed E-STOP loop is mandatory. An unplugged loop must stop and
  disarm the motor output.
- The ESP32 independently stops motors after 250 ms without an accepted drive
  command. The host-side timer is not an adequate substitute.
- `STOP` is accepted irrespective of the current session.
- Driver pins/voltage, encoder input, wheel orientation, and sensor readiness
  cannot be finalized until the physical parts are selected and measured.
- No physical motion was tested here. Firmware has no real motor write routine
  enabled; users must not assume compilation or physical safety.

## Serial messages (ASCII / 115200 baud)

`ARM <16-lowercase-hex-nonce>` starts a new verified session when E-STOP is
closed. `DRV <nonce> <increasing_seq> <left_percent> <right_percent>` requires
both percentages to be integers from -100 to 100. `STOP` always disarms. Each
command is newline terminated. There is **no ACK or robot position feedback** in
this prototype. Add reliable acknowledgements and sensor telemetry before
connecting a real vehicle. The nonce is an anti-stale-session identifier, **not
cryptographic authentication** of a malicious serial peer.

## Validation

Run `python -m unittest tests.test_hardware_boundary -v` at project root. The
Python model tests E-STOP, timeouts, stale sequences, and STOP. It does not
prove firmware-to-Python parity or real motor safety.
