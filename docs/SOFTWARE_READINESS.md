# AutoNav RC: software-readiness review (7 Nov 2026)

## What the supplied source actually contains

- Flutter Android application plus Python/FastAPI *simulation* backend.
- Saved occupancy-grid maps, A*, rerouting, arrival and stop states.
- A development HTTPS controller with one bundled certificate and one pairing token.
- A host-side serial protocol model and an ESP32 **protocol-only** sketch are included in this update; they are NOT connected to the simulator's navigation stack.

## Verified during this update

- `xvfb-run -a python -m unittest discover -s tests -q`: **91 tests passed** in a Linux environment (82 pre-existing + 9 new). The virtual display was required for Tkinter GUI tests.
- `python -m compileall -q api hardware mapping navigation tests`: passed.
- Dart changes were checked against the supplied code; **Flutter SDK was not available here**. Run `flutter analyze && flutter test` on the Mac, then build an APK only after both pass.
- The ESP32 `.ino` file has **not** been compiled with Arduino tools or tested on an ESP32; it intentionally has NO motor-output implementation.

## New build-time controller host configuration

The default Wi-Fi host remains `192.168.1.13`, so existing workflows are unchanged. When you have a DIFFERENT enrolled HTTPS backend with a matching bundled certificate, build with:

```bash
flutter build apk --release --dart-define=AUTONAV_WIFI=true --dart-define=AUTONAV_WIFI_HOST=192.168.1.13
```

You may change `AUTONAV_WIFI_HOST` only alongside a trusted HTTPS certificate containing the new controller's address in Subject Alternative Name, provided securely in `assets/certs/autonav-cert.pem` **locally**. Do **not** upload certificates' private keys to GitHub. Do **not** bypass TLS or use `badCertificateCallback` to make arbitrary hosts connect. This is configuration per build, **not universal runtime discovery**.

### Not yet implemented / not claimable as 100% complete

1. Secure runtime certificate enrollment and per-device identity for arbitrary buyers. The existing pairing manager supports only one in-memory token; server restart invalidates it.
2. Authenticated per-navigation session IDs with explicit ownership transfer and a defined multi-controller takeover protocol.
3. Actual motor control, quadrature encoder, IMU/distance sensor drivers, power-stage E-STOP, physical watchdog and verified motor cut-off.
4. Real indoor localization / SLAM, odometry calibration, collision avoidance based on sensors, and recovery after localization loss.
5. Fully reproducible release setup on a clean machine; the supplied audit archive intentionally omitted private certificates and some platform/build resources.
6. Hardware-in-the-loop and multi-house safety tests.

## Hardware serial protocol (separate prototype)

- `hardware/serial_protocol.py`: testable independent driver interface and host-side session sequence checks; no serial device is opened automatically.
- `hardware/esp32/autonav_rc_esp32.ino`: protocol-validation-only ESP32 sketch. E-STOP input GPIO27 uses `INPUT_PULLUP` and expects a **normally closed** switch to GND. Motors remain unpowered in software because `motorOutputDisabled()` intentionally has no output calls. Pin mapping and motor driver hardware remain undecided.
- `tests/test_hardware_boundary.py`: nine simulated tests for timeout, E-STOP, stale session, sequence, STOP and input validation. The Python reference model is not firmware proof.

## Installation / rollback

- The supplied `apply_update.py` validates original source hashes and saves copies in `.autonav_update_backup/` before changing files.
- This package never modifies `api/main.py`, existing API routes, saved maps, security keys, or the installed APK.
- It does not push code to GitHub automatically.
- Never treat the ESP32 sketch as safe real motor firmware without electrical and hardware validation.
