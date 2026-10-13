import json
from pathlib import Path
import tempfile
import unittest

from slack_notification import build_payload


class SlackNotificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = {
            "id": 123,
            "name": "Sandbox image",
            "head_branch": "main",
            "conclusion": "success",
        }

    def report(self, arch, severities):
        directory = self.root / f"reports-{arch}"
        directory.mkdir()
        (directory / "vulnerabilities.json").write_text(json.dumps({
            "Results": [{"Vulnerabilities": [{"Severity": s} for s in severities]}],
        }))

    def publication(self, version):
        directory = self.root / "publication"
        directory.mkdir()
        (directory / "image.json").write_text(json.dumps({
            "image": "ghcr.io/closytalk/sandbox",
            "version": version,
            "digest": "sha256:" + "a" * 64,
        }))

    def test_every_published_version_is_announced_without_findings(self):
        for version, tag in [("0.1.1", "v0.1.1"), ("execd-1.0.21", "execd-v1.0.21")]:
            with self.subTest(version=version):
                self.publication(version)
                payload = build_payload(self.run, self.root)
                self.assertIn(version, payload["text"])
                self.assertIn(f"/releases/tag/{tag}", json.dumps(payload))
                (self.root / "publication/image.json").unlink()
                (self.root / "publication").rmdir()

    def test_rebuild_versions_are_announced(self):
        self.publication("0.1.0-rebuild.20261013.123.1")
        self.assertIn("0.1.0-rebuild.20261013.123.1", build_payload(self.run, self.root)["text"])

    def test_findings_on_either_architecture_are_reported_even_after_gate_failure(self):
        self.run["conclusion"] = "failure"
        self.report("amd64", ["CRITICAL", "HIGH", "HIGH"])
        self.report("arm64", ["LOW", "UNKNOWN"])
        payload = build_payload(self.run, self.root)
        self.assertIn("amd64: CRITICAL 1, HIGH 2", payload["text"])
        self.assertIn("arm64: LOW 1, UNKNOWN 1", payload["text"])
        self.assertIn("failure", payload["text"])
        self.assertIn("/actions/runs/123", json.dumps(payload))

    def test_publication_and_findings_share_one_message(self):
        self.publication("execd-1.0.20")
        self.report("amd64", ["HIGH"])
        payload = build_payload(self.run, self.root)
        self.assertIn("execd-1.0.20", payload["text"])
        self.assertIn("HIGH 1", payload["text"])

    def test_clean_scans_and_missing_reports_do_not_send_a_message(self):
        self.assertIsNone(build_payload(self.run, self.root))
        self.report("amd64", [])
        self.assertIsNone(build_payload(self.run, self.root))

    def test_trivy_null_vulnerability_lists_are_supported(self):
        directory = self.root / "reports-arm64"
        directory.mkdir()
        (directory / "vulnerabilities.json").write_text(json.dumps({"Results": [{"Vulnerabilities": None}]}))
        self.assertIsNone(build_payload(self.run, self.root))

    def test_ref_names_are_plain_text_and_cannot_mention_the_channel(self):
        self.run["head_branch"] = "<!channel> $(touch /tmp/untrusted)"
        self.report("amd64", ["MEDIUM"])
        payload = build_payload(self.run, self.root)
        self.assertEqual(payload["blocks"][0]["text"]["type"], "plain_text")
        self.assertFalse(payload["mrkdwn"])
        self.assertFalse(payload["unfurl_links"])

    def test_publication_metadata_cannot_inject_external_links(self):
        self.publication("0.1.1")
        path = self.root / "publication/image.json"
        image = json.loads(path.read_text())
        image["version"] = "0.1.1|<!channel>"
        path.write_text(json.dumps(image))
        with self.assertRaisesRegex(ValueError, "Invalid publication metadata"):
            build_payload(self.run, self.root)


if __name__ == "__main__":
    unittest.main()
