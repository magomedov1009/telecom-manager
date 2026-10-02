import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from starlette.requests import Request

from app.routers.pages import login


def _request() -> Request:
    return Request(
        {
            "type": "http",
            "method": "POST",
            "scheme": "https",
            "path": "/login",
            "raw_path": b"/login",
            "query_string": b"",
            "headers": [],
            "client": ("testclient", 50000),
            "server": ("example.test", 443),
            "root_path": "",
        }
    )


class SessionCookieSecurityTest(unittest.TestCase):
    def test_login_marks_cookie_secure_when_configured_for_https(self) -> None:
        user = SimpleNamespace(is_active=True, hashed_password="unused", id=123)
        db = MagicMock()
        db.scalar.return_value = user

        with (
            patch("app.routers.pages.verify_password", return_value=True),
            patch("app.routers.pages.can_access_web_application", return_value=True),
            patch("app.routers.pages.settings.session_cookie_secure", True),
        ):
            response = login(_request(), db, "test-user", "test-password")

        self.assertIn("secure", response.headers["set-cookie"].lower())
        self.assertIn("httponly", response.headers["set-cookie"].lower())

    def test_legacy_http_mode_can_keep_cookie_compatible(self) -> None:
        user = SimpleNamespace(is_active=True, hashed_password="unused", id=123)
        db = MagicMock()
        db.scalar.return_value = user

        with (
            patch("app.routers.pages.verify_password", return_value=True),
            patch("app.routers.pages.can_access_web_application", return_value=True),
            patch("app.routers.pages.settings.session_cookie_secure", False),
        ):
            response = login(_request(), db, "test-user", "test-password")

        self.assertNotIn("secure", response.headers["set-cookie"].lower())


if __name__ == "__main__":
    unittest.main()
