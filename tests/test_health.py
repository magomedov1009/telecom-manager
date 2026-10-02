import unittest
from unittest.mock import patch

from sqlalchemy.exc import SQLAlchemyError

from app.main import create_app


class HealthEndpointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        app = create_app()
        cls.ready_endpoint = next(
            route.endpoint
            for route in app.routes
            if getattr(route, "path", None) == "/health/ready"
        )
        cls.live_endpoint = next(
            route.endpoint
            for route in app.routes
            if getattr(route, "path", None) == "/health/live"
        )

    def test_liveness_does_not_depend_on_the_database(self) -> None:
        response = type(self).live_endpoint()

        self.assertEqual(response, {"status": "ok"})

    def test_readiness_requires_a_successful_database_query(self) -> None:
        with patch("app.main.SessionLocal") as session_factory:
            response = type(self).ready_endpoint()

        session_factory.return_value.execute.assert_called_once()
        session_factory.return_value.close.assert_called_once()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.body, b'{"status":"ready"}')

    def test_readiness_returns_unavailable_without_database_details(self) -> None:
        with patch("app.main.SessionLocal") as session_factory:
            session_factory.return_value.execute.side_effect = SQLAlchemyError(
                "private database diagnostic"
            )
            response = type(self).ready_endpoint()

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.body, b'{"status":"unavailable"}')
        self.assertNotIn(b"private database diagnostic", response.body)
        session_factory.return_value.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
