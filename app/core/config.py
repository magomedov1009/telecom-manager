import re
from functools import lru_cache
from urllib.parse import urlsplit

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL


class Settings(BaseSettings):
    app_name: str = Field(default="Telecom Manager", alias="APP_NAME")
    app_env: str = Field(default="local", alias="APP_ENV")
    app_debug: bool = Field(default=False, alias="APP_DEBUG")
    strict_production_config: bool = Field(
        default=False,
        alias="STRICT_PRODUCTION_CONFIG",
    )
    session_cookie_secure: bool = Field(
        default=False,
        alias="SESSION_COOKIE_SECURE",
    )
    app_secret_key: str = Field(default="local-development-secret-key", alias="APP_SECRET_KEY")

    postgres_host: str = Field(default="localhost", alias="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, alias="POSTGRES_PORT")
    postgres_db: str = Field(default="telecom_manager", alias="POSTGRES_DB")
    postgres_user: str = Field(default="telecom_manager", alias="POSTGRES_USER")
    postgres_password: str = Field(default="telecom_manager_password", alias="POSTGRES_PASSWORD")

    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    # Billing is enabled only for the shared cloud.  A self-hosted copy stays
    # independent of the commercial service and does not require a payment.
    hosting_mode: str = Field(default="self_hosted", alias="HOSTING_MODE")
    cloud_domain: str = Field(default="cloud.example.ru", alias="CLOUD_DOMAIN")
    cloud_trial_days: int = Field(default=14, ge=0, alias="CLOUD_TRIAL_DAYS")
    cloud_monthly_price: int = Field(default=0, ge=0, alias="CLOUD_MONTHLY_PRICE")
    cloud_yearly_price: int = Field(default=0, ge=0, alias="CLOUD_YEARLY_PRICE")
    cloud_payment_link_minutes: int = Field(
        default=60, gt=0, alias="CLOUD_PAYMENT_LINK_MINUTES"
    )
    cloud_payment_provider: str = Field(default="yoomoney", alias="CLOUD_PAYMENT_PROVIDER")
    mobile_login_rate_limit: int = Field(default=30, ge=1, alias="MOBILE_LOGIN_RATE_LIMIT")
    mobile_login_rate_window_seconds: int = Field(
        default=900, gt=0, alias="MOBILE_LOGIN_RATE_WINDOW_SECONDS"
    )
    cloud_registration_rate_limit: int = Field(
        default=5, ge=1, alias="CLOUD_REGISTRATION_RATE_LIMIT"
    )
    cloud_registration_rate_window_seconds: int = Field(
        default=86400, gt=0, alias="CLOUD_REGISTRATION_RATE_WINDOW_SECONDS"
    )
    yoomoney_wallet: str | None = Field(default=None, alias="YOOMONEY_WALLET")
    yoomoney_notification_secret: str | None = Field(
        default=None,
        alias="YOOMONEY_NOTIFICATION_SECRET",
    )
    yoomoney_fallback_notification_url: str | None = Field(
        default=None,
        alias="YOOMONEY_FALLBACK_NOTIFICATION_URL",
    )
    yoomoney_fallback_label_prefixes: str = Field(
        default="",
        alias="YOOMONEY_FALLBACK_LABEL_PREFIXES",
    )
    robokassa_merchant_login: str | None = Field(default=None, alias="ROBOKASSA_MERCHANT_LOGIN")
    robokassa_password1: str | None = Field(default=None, alias="ROBOKASSA_PASSWORD1")
    robokassa_password2: str | None = Field(default=None, alias="ROBOKASSA_PASSWORD2")
    android_release_tag: str = Field(
        default="android-v1.1.1",
        alias="ANDROID_RELEASE_TAG",
    )
    android_apk_download_url: str | None = Field(
        default=None,
        alias="ANDROID_APK_DOWNLOAD_URL",
    )
    bootstrap_clean_demo_provider_catalog: bool = Field(
        default=False,
        alias="BOOTSTRAP_CLEAN_DEMO_PROVIDER_CATALOG",
    )
    bootstrap_clean_cloud_defaults: bool = Field(
        default=False,
        alias="BOOTSTRAP_CLEAN_CLOUD_DEFAULTS",
    )
    support_email: str | None = Field(default=None, alias="SUPPORT_EMAIL")

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.hosting_mode == "cloud":
            domain = self.cloud_domain
            labels = domain.split(".")
            label_pattern = r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
            if (
                domain != domain.strip()
                or len(domain) > 253
                or len(labels) < 2
                or not any(character.isalpha() for character in labels[-1])
                or any(re.fullmatch(label_pattern, label) is None for label in labels)
            ):
                raise ValueError("CLOUD_DOMAIN must be a DNS hostname without scheme or path")
            reserved_production_labels = {"example", "invalid", "localhost", "local", "test"}
            if self.app_env.lower() == "production" and (
                any(label.lower() == "example" for label in labels)
                or labels[-1].lower() in reserved_production_labels
            ):
                raise ValueError("Set the real public CLOUD_DOMAIN for production")
        fallback_url = self.yoomoney_fallback_notification_url
        if fallback_url and (
            self.hosting_mode == "cloud" or self.strict_production_config
        ):
            parsed_fallback = urlsplit(fallback_url)
            if (
                fallback_url != fallback_url.strip()
                or parsed_fallback.scheme.lower() != "https"
                or not parsed_fallback.hostname
                or parsed_fallback.username is not None
                or parsed_fallback.password is not None
                or parsed_fallback.fragment
            ):
                raise ValueError(
                    "YOOMONEY_FALLBACK_NOTIFICATION_URL must be an HTTPS URL "
                    "without embedded credentials or a fragment"
                )
        # Cloud is always a new public deployment and must fail closed. Strict
        # production config is forced by the new self-hosted Compose, while the
        # legacy Compose remains compatible with an existing live installation.
        if self.hosting_mode != "cloud" and not self.strict_production_config:
            return self
        if self.app_env.lower() != "production":
            raise ValueError("APP_ENV must be production for this deployment")
        if self.app_debug:
            raise ValueError("APP_DEBUG must be false in production")
        if not self.session_cookie_secure:
            raise ValueError("SESSION_COOKIE_SECURE must be true in production")
        if (
            self.app_secret_key == "local-development-secret-key"
            or len(self.app_secret_key) < 32
        ):
            raise ValueError("Set a unique APP_SECRET_KEY of at least 32 characters")
        if (
            self.postgres_password == "telecom_manager_password"
            or len(self.postgres_password) < 24
        ):
            raise ValueError("Set a unique POSTGRES_PASSWORD of at least 24 characters")
        if self.postgres_password == self.app_secret_key:
            raise ValueError("APP_SECRET_KEY and POSTGRES_PASSWORD must be different")
        return self

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def database_url(self) -> str:
        return URL.create(
            "postgresql+psycopg",
            username=self.postgres_user,
            password=self.postgres_password,
            host=self.postgres_host,
            port=self.postgres_port,
            database=self.postgres_db,
        ).render_as_string(hide_password=False)

    @property
    def cloud_public_base_url(self) -> str:
        """Use the configured origin instead of a request-controlled Host header."""
        return f"https://{self.cloud_domain}"

    @property
    def yoomoney_fallback_notifications_ready(self) -> bool:
        prefixes = tuple(
            value.strip()
            for value in self.yoomoney_fallback_label_prefixes.split(",")
            if value.strip()
        )
        return not prefixes or bool(
            self.yoomoney_fallback_notification_url
            and self.yoomoney_fallback_notification_url.strip()
        )

    @property
    def cloud_payment_provider_ready(self) -> bool:
        return self.payment_provider_is_ready(self.cloud_payment_provider)

    def payment_provider_is_ready(self, provider: str) -> bool:
        if provider == "yoomoney":
            return bool(
                self.yoomoney_wallet
                and self.yoomoney_notification_secret
                and self.yoomoney_fallback_notifications_ready
            )
        if provider == "robokassa":
            return bool(
                self.robokassa_merchant_login
                and self.robokassa_password1
                and self.robokassa_password2
            )
        return False


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
