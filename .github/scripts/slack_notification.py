"""Compose Slack messages from publication metadata and Trivy JSON reports."""

from collections import Counter
import json
import os
from pathlib import Path
import re


def summarise(counts):
    return ", ".join(f"{severity} {counts[severity]}" for severity in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN") if counts[severity])


def build_payload(run, artifact_directory, job_results=None):
    directory = Path(artifact_directory)
    lines = []
    links = []
    if run["conclusion"] == "failure":
        failed = sorted(job for job, need in (job_results or {}).items() if need.get("result") == "failure")
        lines.append(f'❌ {run["name"]}: controlli falliti' + (f' ({", ".join(failed)})' if failed else ""))
    publication = directory / "publication" / "image.json"
    if publication.is_file():
        image = json.loads(publication.read_text())
        version = image["version"]
        if (
            image["image"] != "ghcr.io/closytalk/sandbox"
            or not re.fullmatch(r"(?:execd-)?\d+\.\d+\.\d+(?:-rebuild\.\d{8}\.\d+\.\d+)?", version)
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", image["digest"])
        ):
            raise ValueError("Invalid publication metadata")
        tag = "execd-v" + version.removeprefix("execd-") if version.startswith("execd-") else "v" + version
        lines.extend([f"✅ Nuova versione pubblicata: {version}", f'{image["image"]}:{version}', image["digest"]])
        links.append(f"<https://github.com/ClosyTalk/sandbox-image/releases/tag/{tag}|Release e report>")

    findings = []
    any_fixable = False
    # reports-<arch> from the build workflows, reports-<version>-<arch> from the
    # nightly scan of published releases.
    for report in sorted(directory.glob("reports-*/vulnerabilities.json")):
        label = report.parent.name.removeprefix("reports-")
        if not re.fullmatch(r"(?:(?:execd-)?\d+\.\d+\.\d+-)?(?:amd64|arm64)", label):
            raise ValueError("Invalid report name")
        results = json.loads(report.read_text()).get("Results") or []
        counts = {True: Counter(), False: Counter()}
        for result in results:
            for vulnerability in result.get("Vulnerabilities") or []:
                fixable = vulnerability.get("Status") == "fixed" or bool(vulnerability.get("FixedVersion"))
                counts[fixable][vulnerability.get("Severity", "UNKNOWN")] += 1
        groups = [
            f"{label}: {summarise(counts[fixable])}"
            for fixable, label in ((True, "con correzione"), (False, "senza correzione"))
            if counts[fixable]
        ]
        if groups:
            any_fixable = any_fixable or bool(counts[True])
            findings.append(f"{label} — " + " · ".join(groups))
    if findings:
        title = (
            "⚠️ Vulnerabilità con correzione disponibile"
            if any_fixable
            else "ℹ️ Solo vulnerabilità senza correzione del fornitore"
        )
        lines.extend([f'{title} — {run["name"]}', *findings])
        lines.append("CRITICAL blocca la pubblicazione; le altre severità sono segnalate.")
    if not lines:
        return None

    lines.append(f'Ref: {run["head_branch"]} · Esito pipeline: {run["conclusion"]}')
    run_id = int(run["id"])
    links.append(f"<https://github.com/ClosyTalk/sandbox-image/actions/runs/{run_id}|Pipeline e artefatti>")
    text = "\n".join(lines)
    return {
        "text": text,
        "mrkdwn": False,
        "unfurl_links": False,
        "unfurl_media": False,
        "blocks": [
            {"type": "section", "text": {"type": "plain_text", "text": text}},
            {"type": "section", "text": {"type": "mrkdwn", "text": " · ".join(links)}},
        ],
    }


if __name__ == "__main__":
    run = {
        "id": os.environ["GITHUB_RUN_ID"],
        "name": os.environ["GITHUB_WORKFLOW"],
        "head_branch": os.environ["GITHUB_REF_NAME"],
        "conclusion": os.environ["PIPELINE_RESULT"],
    }
    job_results = json.loads(os.environ.get("JOB_RESULTS") or "{}")
    payload = build_payload(run, os.environ["ARTIFACT_DIRECTORY"], job_results)
    if payload:
        Path(os.environ["PAYLOAD_PATH"]).write_text(json.dumps(payload))
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"notify={'true' if payload else 'false'}\n")
