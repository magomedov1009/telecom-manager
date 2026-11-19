from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class ContinuousIntegrationWorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        workflow_path = ROOT / ".github/workflows/backend.yml"
        self.workflow_text = workflow_path.read_text(encoding="utf-8")
        with workflow_path.open(encoding="utf-8") as stream:
            self.workflow = yaml.safe_load(stream)

    def test_push_trigger_runs_for_feature_branches(self) -> None:
        self.assertRegex(
            self.workflow_text,
            r'push:\s*\n\s*branches:\s*\["\*\*"\]',
        )

    def test_github_actions_are_pinned_to_full_commit_shas(self) -> None:
        steps = [
            step
            for job in self.workflow["jobs"].values()
            for step in job.get("steps", [])
        ]
        actions = [step["uses"] for step in steps if step.get("uses")]

        self.assertGreaterEqual(len(actions), 3)
        for action in actions:
            with self.subTest(action=action):
                self.assertRegex(
                    action,
                    re.compile(r"^[\w.-]+/[\w.-]+@[0-9a-f]{40}$"),
                )

    def test_mobile_job_analyzes_tests_and_builds_without_publishing(self) -> None:
        steps = self.workflow["jobs"]["mobile"]["steps"]
        run_commands = [step.get("run", "") for step in steps]
        flutter_setup = next(
            step for step in steps if step.get("uses", "").startswith("flutter-actions/")
        )

        self.assertEqual(flutter_setup["with"]["version"], "3.44.4")
        self.assertNotIn("cache", flutter_setup.get("with", {}))
        self.assertNotIn("cache-sdk", flutter_setup.get("with", {}))
        self.assertIn("flutter pub get --enforce-lockfile", run_commands)
        self.assertIn("flutter analyze", run_commands)
        self.assertIn("flutter test", run_commands)
        self.assertIn("flutter build apk --release --flavor direct --no-pub", run_commands)
        self.assertIn(
            "flutter build appbundle --release --flavor play --no-pub",
            run_commands,
        )
        self.assertFalse(any("PLAY_STORE_RELEASE" in command for command in run_commands))
        self.assertFalse(any("upload" in step.get("name", "").lower() for step in steps))

    def test_workflow_runs_isolated_postgres_restore_check(self) -> None:
        steps = self.workflow["jobs"]["backend"]["steps"]
        restore_steps = [
            step
            for step in steps
            if "scripts/restore-test-cloud.sh" in step.get("run", "")
        ]

        self.assertEqual(len(restore_steps), 1)
        self.assertIn("pg_dump -Fc", restore_steps[0]["run"])
        self.assertEqual(
            self.workflow["jobs"]["backend"]["services"]["postgres"]["image"],
            "postgres:16-alpine",
        )
        self.assertEqual(
            self.workflow["jobs"]["backend"]["env"][
                "BOOTSTRAP_CLEAN_DEMO_PROVIDER_CATALOG"
            ],
            "true",
        )
        migration_step = next(
            step
            for step in steps
            if step.get("name") == "Apply migrations to PostgreSQL"
        )
        self.assertEqual(migration_step["env"]["HOSTING_MODE"], "cloud")
        self.assertEqual(
            migration_step["env"]["BOOTSTRAP_CLEAN_CLOUD_DEFAULTS"], "true"
        )
        self.assertEqual(migration_step["env"]["APP_ENV"], "production")


if __name__ == "__main__":
    unittest.main()
