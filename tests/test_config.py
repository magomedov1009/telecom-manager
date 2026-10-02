import unittest

from alembic.config import Config
from pydantic import ValidationError
from sqlalchemy.engine import make_url

from app.core.config import Settings


class DatabaseUrlTest(unittest.TestCase):
    def test_cloud_bootstrap_cleanup_is_opt_in(self) -> None:
        self.assertFalse(Settings().bootstrap_clean_cloud_defaults)
        enabled = Settings(BOOTSTRAP_CLEAN_CLOUD_DEFAULTS=True)
        self.assertTrue(enabled.bootstrap_clean_cloud_defaults)

    def test_reserved_password_characters_survive_sqlalchemy_and_alembic(self) -> None:
        password = "p@ss:/%#word"
        settings = Settings(
            POSTGRES_HOST="db.example.test",
            POSTGRES_PORT=5432,
            POSTGRES_DB="telecom_test",
            POSTGRES_USER="telecom_test",
            POSTGRES_PASSWORD=password,
        )

        url = settings.database_url
        self.assertEqual(make_url(url).password, password)

        alembic_config = Config()
        alembic_config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))
        self.assertEqual(alembic_config.get_main_option("sqlalchemy.url"), url)

    def test_cloud_production_rejects_template_secrets(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                APP_ENV="production",
                APP_DEBUG=False,
                HOSTING_MODE="cloud",
                CLOUD_DOMAIN="telecom.pmguard.ru",
                SESSION_COOKIE_SECURE=True,
                APP_SECRET_KEY="local-development-secret-key",
                POSTGRES_PASSWORD="telecom_manager_password",
            )

    def test_cloud_production_accepts_strong_secrets(self) -> None:
        settings = Settings(
            APP_ENV="production",
            APP_DEBUG=False,
            HOSTING_MODE="cloud",
            CLOUD_DOMAIN="telecom.pmguard.ru",
            SESSION_COOKIE_SECURE=True,
            APP_SECRET_KEY="cloud-app-secret-" + "a" * 32,
            POSTGRES_PASSWORD="cloud-database-password-" + "b" * 24,
        )
        self.assertEqual(settings.hosting_mode, "cloud")

    def test_cloud_production_rejects_unencrypted_yoomoney_fallback(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                APP_ENV="production",
                APP_DEBUG=False,
                HOSTING_MODE="cloud",
            CLOUD_DOMAIN="telecom.pmguard.ru",
                SESSION_COOKIE_SECURE=True,
                APP_SECRET_KEY="cloud-app-secret-" + "a" * 32,
                POSTGRES_PASSWORD="cloud-database-password-" + "b" * 24,
                YOOMONEY_FALLBACK_NOTIFICATION_URL="http://payments.example.test/callback",
            )

    def test_cloud_production_accepts_https_yoomoney_fallback(self) -> None:
        settings = Settings(
            APP_ENV="production",
            APP_DEBUG=False,
            HOSTING_MODE="cloud",
            CLOUD_DOMAIN="telecom.pmguard.ru",
            SESSION_COOKIE_SECURE=True,
            APP_SECRET_KEY="cloud-app-secret-" + "a" * 32,
            POSTGRES_PASSWORD="cloud-database-password-" + "b" * 24,
            YOOMONEY_FALLBACK_NOTIFICATION_URL=(
                "https://payments.example.test/payments/webhook"
            ),
        )
        self.assertTrue(settings.yoomoney_fallback_notifications_ready)

    def test_robokassa_checkout_readiness_uses_its_own_secrets(self) -> None:
        settings = Settings(
            CLOUD_PAYMENT_PROVIDER="robokassa",
            ROBOKASSA_MERCHANT_LOGIN="telecom-shop",
            ROBOKASSA_PASSWORD1="checkout-secret",
            ROBOKASSA_PASSWORD2="notification-secret",
        )
        self.assertTrue(settings.cloud_payment_provider_ready)
        self.assertFalse(settings.payment_provider_is_ready("yoomoney"))

        unavailable = Settings(CLOUD_PAYMENT_PROVIDER="robokassa")
        self.assertFalse(unavailable.cloud_payment_provider_ready)

    def test_cloud_domain_must_be_a_hostname_not_a_url(self) -> None:
        invalid_domains = (
            "https://telecom.pmguard.ru",
            "telecom.pmguard.ru/path",
            "telecom..pmguard.ru",
            "attacker.example@telecom.pmguard.ru",
            "192.0.2.1",
        )
        for domain in invalid_domains:
            with self.subTest(domain=domain), self.assertRaises(ValidationError):
                Settings(HOSTING_MODE="cloud", CLOUD_DOMAIN=domain)

    def test_cloud_production_rejects_reserved_domain(self) -> None:
        for domain in ("cloud.example.ru", "cloud.test", "cloud.invalid", "cloud.local"):
            with self.subTest(domain=domain), self.assertRaises(ValidationError):
                Settings(
                    APP_ENV="production",
                    APP_DEBUG=False,
                    HOSTING_MODE="cloud",
                    CLOUD_DOMAIN=domain,
                    SESSION_COOKIE_SECURE=True,
                    APP_SECRET_KEY="cloud-app-secret-" + "a" * 32,
                    POSTGRES_PASSWORD="cloud-database-password-" + "b" * 24,
                )

    def test_existing_self_hosted_defaults_are_not_blocked(self) -> None:
        settings = Settings(
            APP_ENV="production",
            APP_DEBUG=False,
            HOSTING_MODE="self_hosted",
        )
        self.assertEqual(settings.hosting_mode, "self_hosted")

    def test_new_self_hosted_production_rejects_template_secrets(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                APP_ENV="production",
                APP_DEBUG=False,
                STRICT_PRODUCTION_CONFIG=True,
                HOSTING_MODE="self_hosted",
                SESSION_COOKIE_SECURE=True,
            )

    def test_new_self_hosted_production_accepts_strong_secrets(self) -> None:
        settings = Settings(
            APP_ENV="production",
            APP_DEBUG=False,
            STRICT_PRODUCTION_CONFIG=True,
            HOSTING_MODE="self_hosted",
            SESSION_COOKIE_SECURE=True,
            APP_SECRET_KEY="self-hosted-app-secret-" + "a" * 32,
            POSTGRES_PASSWORD="self-hosted-database-password-" + "b" * 24,
        )
        self.assertEqual(settings.hosting_mode, "self_hosted")

    def test_new_production_deployment_rejects_insecure_session_cookie(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                APP_ENV="production",
                APP_DEBUG=False,
                STRICT_PRODUCTION_CONFIG=True,
                HOSTING_MODE="self_hosted",
                SESSION_COOKIE_SECURE=False,
                APP_SECRET_KEY="self-hosted-app-secret-" + "a" * 32,
                POSTGRES_PASSWORD="self-hosted-database-password-" + "b" * 24,
            )

    def test_billing_settings_reject_invalid_ranges(self) -> None:
        invalid_settings = (
            {"CLOUD_TRIAL_DAYS": -1},
            {"CLOUD_MONTHLY_PRICE": -1},
            {"CLOUD_YEARLY_PRICE": -1},
            {"CLOUD_PAYMENT_LINK_MINUTES": 0},
            {"MOBILE_LOGIN_RATE_LIMIT": 0},
            {"MOBILE_LOGIN_RATE_WINDOW_SECONDS": 0},
            {"CLOUD_REGISTRATION_RATE_LIMIT": 0},
            {"CLOUD_REGISTRATION_RATE_WINDOW_SECONDS": 0},
        )
        for values in invalid_settings:
            with self.subTest(values=values), self.assertRaises(ValidationError):
                Settings(**values)


if __name__ == "__main__":
    unittest.main()
