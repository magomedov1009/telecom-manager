from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


def load_compose(filename: str) -> dict:
    with (ROOT / filename).open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


class ComposeSecurityTests(unittest.TestCase):
    def test_legacy_cloud_and_self_hosted_profiles_do_not_collide(self) -> None:
        filenames = (
            "docker-compose.yml",
            "docker-compose.cloud.yml",
            "docker-compose.self-hosted.yml",
        )
        container_names = []
        published_endpoints = []
        for filename in filenames:
            compose = load_compose(filename)
            for service in compose["services"].values():
                if service.get("container_name"):
                    container_names.append(service["container_name"])
                for port in service.get("ports", []):
                    if isinstance(port, str):
                        published_endpoints.append(port)
                    else:
                        published_endpoints.append(
                            f"{port.get('host_ip', '0.0.0.0')}:{port['published']}"
                        )

        self.assertEqual(len(container_names), len(set(container_names)))
        self.assertEqual(len(published_endpoints), len(set(published_endpoints)))

    def test_postgres_is_never_published_to_the_host(self) -> None:
        for filename in (
            "docker-compose.yml",
            "docker-compose.cloud.yml",
            "docker-compose.self-hosted.yml",
        ):
            with self.subTest(compose=filename):
                compose = load_compose(filename)
                self.assertNotIn("ports", compose["services"]["postgres"])

    def test_production_app_ports_are_loopback_only(self) -> None:
        expected = {
            "docker-compose.cloud.yml": "127.0.0.1:8001:8000",
            "docker-compose.self-hosted.yml": "127.0.0.1:8002:8000",
        }
        for filename, port_mapping in expected.items():
            with self.subTest(compose=filename):
                compose = load_compose(filename)
                self.assertIn(
                    port_mapping,
                    compose["services"]["app"]["ports"],
                )

    def test_cloud_database_is_not_connected_to_proxy_network(self) -> None:
        compose = load_compose("docker-compose.cloud.yml")
        self.assertNotIn(
            "cloud_edge",
            compose["services"]["postgres"]["networks"],
        )
        self.assertEqual(
            set(compose["services"]["app"]["networks"]),
            {"cloud_private", "cloud_edge"},
        )
        self.assertEqual(
            compose["services"]["https_proxy"]["networks"],
            ["cloud_edge"],
        )
        self.assertEqual(
            compose["services"]["postgres"]["networks"],
            ["cloud_private"],
        )

    def test_cloud_startup_waits_for_database_and_application_readiness(self) -> None:
        compose = load_compose("docker-compose.cloud.yml")
        app = compose["services"]["app"]
        proxy = compose["services"]["https_proxy"]

        self.assertEqual(
            app["depends_on"]["postgres"]["condition"],
            "service_healthy",
        )
        healthcheck = " ".join(app["healthcheck"]["test"])
        self.assertIn("/health/ready", healthcheck)
        self.assertEqual(
            proxy["depends_on"]["app"]["condition"],
            "service_healthy",
        )


class RestoreScriptSecurityTests(unittest.TestCase):
    def test_restore_probe_is_isolated_and_removes_only_its_container(self) -> None:
        script = (ROOT / "scripts/restore-test-cloud.sh").read_text(encoding="utf-8")

        self.assertIn("--network none", script)
        self.assertNotRegex(script, r"(?m)^\s*--(?:publish|volume)\b")
        self.assertIn('docker rm --force "$container_name"', script)
        self.assertIn("pg_restore --exit-on-error --no-owner --no-privileges", script)
        self.assertIn('< "$archive"', script)
        self.assertIn("SELECT version_num FROM alembic_version", script)


class BackupScriptSecurityTests(unittest.TestCase):
    def test_local_pruning_happens_only_after_verified_offsite_copy(self) -> None:
        script = (ROOT / "scripts/backup-cloud.sh").read_text(encoding="utf-8")

        copy_position = script.index("rclone copyto --immutable")
        verify_position = script.index("rclone check --one-way")
        prune_position = script.index("find \"$backup_dir\" -maxdepth 1 -type f")
        self.assertLess(copy_position, verify_position)
        self.assertLess(verify_position, prune_position)
        self.assertIn("-name 'cloud-backup-*.dump'", script)
        self.assertIn('-mmin "+$((local_retention_days * 1440))"', script)
        self.assertIn("LOCAL_BACKUP_RETENTION_DAYS:-7", script)


class RepositorySecretHygieneTests(unittest.TestCase):
    def test_signing_keys_and_certificates_are_excluded_from_git_and_images(self) -> None:
        expected = {"*.jks", "*.keystore", "*.p12", "*.pfx", "*.pem", "*.key"}
        gitignore = set((ROOT / ".gitignore").read_text(encoding="utf-8").splitlines())
        dockerignore = set((ROOT / ".dockerignore").read_text(encoding="utf-8").splitlines())

        self.assertTrue(expected.issubset(gitignore))
        self.assertTrue(expected.issubset(dockerignore))
        self.assertIn(".env.*", gitignore)
        self.assertIn("!.env.example", gitignore)
        self.assertIn(".env.*", dockerignore)
        self.assertIn("!.env.example", dockerignore)


if __name__ == "__main__":
    unittest.main()
