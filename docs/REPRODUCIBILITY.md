# Reproducing the AutoNav RC simulator

## Python

Create a virtual environment with Python 3.12 or newer. Install packages from `requirements-dev.txt` and run:

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -q
```

Some map visualizer tests depend on Tkinter and a display server. On a headless Linux runner, install `python3-tk` and `xvfb`, then run tests through `xvfb-run -a`.

## Android

The Flutter application lives in `mobile_app/autonav_rc`. Use an installed Flutter SDK compatible with the Dart SDK specified in `pubspec.yaml`. Run:

```bash
cd mobile_app/autonav_rc
flutter pub get
flutter analyze
flutter test
```

**Important:** The Android Wi-Fi client loads `assets/certs/autonav-cert.pem`. It is deliberately not committed: the current project uses a development-specific trusted certificate. On your private machine, keep the matching certificate in that asset path. New users need an independent, secure onboarding/provisioning process. Do NOT disable TLS certificate verification to make builds connect.

The current source snapshot may still need normal Flutter platform scaffolding, generated assets, or native configuration before every supported platform can build cleanly. Public CI currently tests Python only; Flutter CI should be enabled when a safe mock trust asset is configured for tests.

## Device connection

The current development controller defaults to a particular LAN endpoint. Actual connection requires the corresponding backend, network access, certificate trust and pairing. An APK alone is not an independently running autonomous robot.
