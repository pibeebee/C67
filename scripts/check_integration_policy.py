"""Reject main promotions that are not same-repository dev pull requests."""
import json
import os
from pathlib import Path


def validate_promotion(event_name, event, repository):
    if event_name != "pull_request" or not repository:
        raise ValueError("Integration requires a pull request event and repository identity.")
    pr = event.get("pull_request") or {}
    head, base = pr.get("head") or {}, pr.get("base") or {}
    if head.get("ref") != "dev" or base.get("ref") != "main":
        raise ValueError("Only dev -> main promotion pull requests are allowed.")
    if any((side.get("repo") or {}).get("full_name") != repository for side in (head, base)):
        raise ValueError("Promotion must originate in the same repository.")


if __name__ == "__main__":
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        validate_promotion(os.environ.get("GITHUB_EVENT_NAME"), event, os.environ.get("GITHUB_REPOSITORY"))
    except (KeyError, OSError, ValueError, TypeError, AttributeError) as error:
        raise SystemExit(str(error)) from error
    print("Verified same-repository dev -> main promotion.")
