import asyncio
import unittest

from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware


class ProxyHeadersTest(unittest.TestCase):
    def test_trusted_reverse_proxy_sets_external_https_scheme(self) -> None:
        observed = {}

        async def app(scope, _receive, _send):
            observed["scheme"] = scope["scheme"]

        middleware = ProxyHeadersMiddleware(app, trusted_hosts="*")
        scope = {
            "type": "http",
            "scheme": "http",
            "client": ("172.28.0.3", 41000),
            "server": ("172.28.0.2", 8000),
            "headers": [(b"x-forwarded-proto", b"https")],
        }

        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def send(_message):
            return None

        asyncio.run(middleware(scope, receive, send))

        self.assertEqual(observed["scheme"], "https")


if __name__ == "__main__":
    unittest.main()
