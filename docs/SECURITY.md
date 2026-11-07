# Security boundaries

- This repository is a software simulator and hardware-facing development prototype; it is not a proven safety-critical vehicle controller.
- Never commit backend private TLS keys, pairing tokens, real device certificates, Wi-Fi passwords, or credential-containing `.env` files.
- Certificate validation must remain enabled. Per-device enrollment and certificate provisioning are not complete.
- Safety checks for simulated motion do not replace independent physical emergency-stop and motor watchdog circuitry.
- A new physical motor-control firmware image must remain disabled until sensor, drivetrain, and fail-safe hardware are assembled and tested.
- The public GitHub Pages website is informational. The development APK may be bound to an individual backend.

## Reporting security issues

Do not open public issues containing credentials or exploit details. Contact the repository maintainer through their GitHub profile to coordinate a responsible report.
