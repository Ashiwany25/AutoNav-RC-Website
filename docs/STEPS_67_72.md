# AutoNav RC: consolidated offline software integration (Steps 67–72)

## Implemented

- **67 – range-to-grid mapping:** ray updates from simulated planar range samples; unknown cells remain blocked; obstacles are not erased by a single free return; invalid scans are rejected before changing the grid.
- **68 – odometry and heading inputs:** `LocalizationPipeline` composes validated telemetry, wheel odometry, optional calibrated heading measurement, and optional range mapping. It does NOT establish global pose confidence.
- **69 – localized path proposal:** `LocalizedPlanner` accepts only explicitly trustworthy, fresh pose estimates and routes via the existing obstacle-clearance-aware planner. It does NOT drive wheels.
- **70 – serial command gateway:** `SimulatedMotorGateway` exercises the earlier motor protocol against a Python firmware watchdog model, with an explicit test E-stop loop. It does NOT connect hardware.
- **71 – session safety foundation:** simulated serial session nonces, monotonic command sequences, E-stop and timeout safety checks. Production pairing/provisioning and full HTTP controller-lease coverage remain unfinished.
- **72 – regression tests and packaging:** isolated tests, additive installer, and development documentation.

## Sensor frames and limitations

- Grid coordinates: (row, column), 0-based; world meters: x = column direction, y = row direction.
- Initial pose is in the map's frame; the estimator does **not** solve map alignment, loop closure, or SLAM.
- Set trustworthy=True **only after** external calibrated localization and quality assessment. This batch intentionally returns `trustworthy=False` from the odometry pipeline.
- Readings do not capture an actual LiDAR or ultrasonic sensor until real drivers and calibration are implemented.
- No real motors are enabled; no hardware has been validated.

## Android compatibility

The working Android app, FastAPI routes, saved map and simulator code are deliberately unchanged. No APK rebuild is necessary for these additive offline modules; a future hardware-enabled app requires dedicated end-to-end tests and controller onboarding.

## Before physical operation

- Hardware-specific driver and wiring validation, independent motor power cut and tested normally-closed E-stop.
- Sensor calibration, encoder sign and wheel geometry validation, localization uncertainty and mapping drift assessment.
- Authentication / ownership enforcement on all actuator endpoints, safe handover policy and secured device certificate enrollment.
- Real watchdog tests under power loss, network loss, stalled process, corrupt telemetry, collisions and sensor failure.
