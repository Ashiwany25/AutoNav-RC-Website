
import hashlib
import os
import secrets
import threading
import time

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field


class PairRequest(BaseModel):
    code: str = Field(min_length=6, max_length=6)


class PairingManager:
    def __init__(
        self,
        code_lifetime=300,
        token_lifetime=86400,
        max_attempts=5,
    ):
        self.code_lifetime = code_lifetime
        self.token_lifetime = token_lifetime
        self.max_attempts = max_attempts
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        with self.lock:
            self.code = (
                f"{secrets.randbelow(1000000):06d}"
            )
            self.code_deadline = (
                time.monotonic() + self.code_lifetime
            )
            self.attempts = 0
            self.token_hash = None
            self.token_deadline = 0.0

    def pair(self, code):
        with self.lock:
            now = time.monotonic()

            if self.code is None:
                return None, "Code already used"

            if now >= self.code_deadline:
                return None, "Pairing code expired"

            if self.attempts >= self.max_attempts:
                return None, "Too many attempts"

            self.attempts += 1

            if not secrets.compare_digest(
                str(code), self.code
            ):
                return None, "Invalid pairing code"

            token = secrets.token_urlsafe(32)

            self.token_hash = hashlib.sha256(
                token.encode()
            ).hexdigest()

            self.token_deadline = (
                now + self.token_lifetime
            )

            # Single-use pairing code.
            self.code = None

            return token, None

    def validate(self, token):
        if not token:
            return False

        with self.lock:
            if (
                self.token_hash is None
                or time.monotonic()
                >= self.token_deadline
            ):
                return False

            submitted_hash = hashlib.sha256(
                token.encode()
            ).hexdigest()

            return secrets.compare_digest(
                submitted_hash,
                self.token_hash,
            )


def install_local_pairing(app):
    enabled = (
        os.getenv(
            "AUTONAV_PAIRING_ENABLED", "0"
        ) == "1"
    )

    manager = PairingManager()
    router = APIRouter(
        prefix="/api/v1/pairing",
        tags=["Local Device Pairing"],
    )

    @router.get("/status")
    async def pairing_status():
        return {
            "success": True,
            "pairing_enabled": enabled,
            "paired": (
                manager.token_hash is not None
            ),
        }

    @router.post("/connect")
    async def pairing_connect(
        request: Request,
        body: PairRequest,
    ):
        if not enabled:
            return JSONResponse(
                status_code=503,
                content={
                    "detail": "Pairing not enabled"
                },
            )

        # This stage permits initial pairing
        # only through a loopback connection,
        # such as USB/ADB reverse.
        client_host = (
            request.client.host
            if request.client
            else ""
        )

        if (
            client_host not in ("127.0.0.1", "::1")
            and request.url.scheme != "https"
        ):
            return JSONResponse(
                status_code=403,
                content={
                    "detail": (
                        "Initial pairing requires "
                        "a local trusted connection"
                    )
                },
            )

        token, error = manager.pair(
            body.code
        )

        if error:
            return JSONResponse(
                status_code=403,
                content={"detail": error},
            )

        return {
            "success": True,
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": (
                manager.token_lifetime
            ),
        }

    app.include_router(router)

    @app.middleware("http")
    async def pairing_authentication(
        request: Request,
        call_next,
    ):
        if not enabled:
            return await call_next(request)

        path = request.url.path

        public_paths = {
            "/api/v1/health",
            "/api/v1/pairing/status",
            "/api/v1/pairing/connect",
        }

        if (
            not path.startswith("/api/v1/")
            or path in public_paths
        ):
            return await call_next(request)

        authorization = request.headers.get(
            "authorization", ""
        )

        scheme, separator, token = (
            authorization.partition(" ")
        )

        if (
            not separator
            or scheme.lower() != "bearer"
            or not manager.validate(token)
        ):
            return JSONResponse(
                status_code=401,
                content={
                    "detail": (
                        "Valid device pairing "
                        "token required"
                    )
                },
                headers={
                    "WWW-Authenticate": "Bearer"
                },
            )

        # Identity comes only from the validated bearer token.
        # Never trust a controller ID supplied in an HTTP header.
        request.state.controller_id = hashlib.sha256(
            token.encode()
        ).hexdigest()

        return await call_next(request)

    if enabled:
        print(
            "\nAutoNav RC local pairing enabled."
        )
        print(
            "Pairing code (5-minute expiry): "
            + manager.code
        )
        print(
            "Use only through localhost/USB "
            "until encrypted Wi-Fi is configured.\n"
        )

    return manager
