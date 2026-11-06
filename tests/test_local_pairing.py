
import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from api.local_pairing import (
    PairingManager,
    install_local_pairing,
)


class TestPairingManager(unittest.TestCase):
    def test_correct_code_creates_token(self):
        manager = PairingManager()

        token, error = manager.pair(manager.code)

        self.assertIsNone(error)
        self.assertTrue(token)
        self.assertTrue(manager.validate(token))

    def test_wrong_code_rejected(self):
        manager = PairingManager()

        wrong = (
            "000000"
            if manager.code != "000000"
            else "999999"
        )

        token, error = manager.pair(wrong)

        self.assertIsNone(token)
        self.assertEqual(
            error,
            "Invalid pairing code",
        )

    def test_code_cannot_be_reused(self):
        manager = PairingManager()
        code = manager.code

        token, error = manager.pair(code)
        self.assertIsNone(error)

        second, error = manager.pair(code)

        self.assertIsNone(second)
        self.assertEqual(
            error,
            "Code already used",
        )

    def test_invalid_token_rejected(self):
        manager = PairingManager()
        token, _ = manager.pair(manager.code)

        self.assertTrue(manager.validate(token))
        self.assertFalse(
            manager.validate("invalid-token")
        )

    def test_expired_code_rejected(self):
        manager = PairingManager(
            code_lifetime=0
        )

        token, error = manager.pair(
            manager.code
        )

        self.assertIsNone(token)
        self.assertEqual(
            error,
            "Pairing code expired",
        )

    def test_too_many_attempts(self):
        manager = PairingManager(
            max_attempts=2
        )

        wrong = (
            "000000"
            if manager.code != "000000"
            else "999999"
        )

        manager.pair(wrong)
        manager.pair(wrong)

        token, error = manager.pair(
            manager.code
        )

        self.assertIsNone(token)
        self.assertEqual(
            error,
            "Too many attempts",
        )

    def test_reset_invalidates_old_token(self):
        manager = PairingManager()
        token, _ = manager.pair(manager.code)

        manager.reset()

        self.assertFalse(manager.validate(token))


class TestPairingAPI(
    unittest.IsolatedAsyncioTestCase
):
    async def asyncSetUp(self):
        self.env = patch.dict(
            os.environ,
            {"AUTONAV_PAIRING_ENABLED": "1"},
        )
        self.env.start()

        self.app = FastAPI()

        @self.app.get("/api/v1/private")
        async def private_endpoint():
            return {"success": True}

        self.manager = install_local_pairing(
            self.app
        )

        self.client = AsyncClient(
            transport=ASGITransport(
                app=self.app
            ),
            base_url="http://127.0.0.1",
        )

    async def asyncTearDown(self):
        await self.client.aclose()
        self.env.stop()

    async def test_unauthenticated_rejected(self):
        response = await self.client.get(
            "/api/v1/private"
        )

        self.assertEqual(
            response.status_code,
            401,
        )

    async def test_authenticated_access(self):
        response = await self.client.post(
            "/api/v1/pairing/connect",
            json={
                "code": self.manager.code
            },
        )

        self.assertEqual(
            response.status_code,
            200,
        )

        token = response.json()[
            "access_token"
        ]

        protected = await self.client.get(
            "/api/v1/private",
            headers={
                "Authorization": (
                    f"Bearer {token}"
                )
            },
        )

        self.assertEqual(
            protected.status_code,
            200,
        )

    async def test_status_is_public(self):
        response = await self.client.get(
            "/api/v1/pairing/status"
        )

        self.assertEqual(
            response.status_code,
            200,
        )

        self.assertTrue(
            response.json()[
                "pairing_enabled"
            ]
        )


if __name__ == "__main__":
    unittest.main()
