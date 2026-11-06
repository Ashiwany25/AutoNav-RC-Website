# AutoNav RC — Simulator Release

## Included
- `AutoNav-RC.apk`: Flutter Android release build
- `index.html`: static download website
- `SHA256SUMS.txt`: APK integrity checksum

## Verified before packaging
- Python backend: 82 tests passed
- Flutter: 104 tests passed
- Flutter analysis: no issues
- Android release APK compiled successfully

These results were reported by the developer's build logs;
this packaging script does not rerun those tests.

## Requirements
- Android phone
- MacBook running the AutoNav RC FastAPI backend
- Same local Wi-Fi network
- Valid paired-controller credentials

## Current development controller
- HTTPS endpoint: https://192.168.1.13:8443
- Certificate is specific to the existing development backend.
- Restarting backend may require a new pairing code.

## Start the existing development backend
From the AutoNav-RC project root:

```bash
AUTONAV_PAIRING_ENABLED=1 AUTONAV_DEDICATED_HEARTBEAT=1 \
.venv/bin/python -m uvicorn api.main:app \
--host 192.168.1.13 --port 8443 \
--ssl-keyfile security/autonav-key.pem \
--ssl-certfile security/autonav-cert.pem
```

The command requires that the Mac still owns the IP address
192.168.1.13 and the matching development certificate.

## Website deployment
To use GitHub Pages, publish these release_site files from a
repository or configured Pages folder.

Do not publicly distribute this development APK as a general-purpose
RC-car controller. First implement per-device onboarding, secure
certificate provisioning, production signing and real hardware safety.

## Limitations
- Indoor movement is currently simulated.
- Hardware SLAM, sensors, motors and firmware are not yet integrated.
- Physical motor emergency stop is not yet implemented.
- General consumer controller onboarding is not complete.
