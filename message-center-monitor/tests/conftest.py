"""pytest fixtures and sys.path shim for message-center-monitor tests."""
from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SOLUTION_DIR = Path(__file__).resolve().parents[1]

# Ensure both shared/ and the solution's scripts/ are importable.
for p in (REPO_ROOT / "scripts" / "shared", SOLUTION_DIR / "scripts"):
    sp = str(p)
    if sp not in sys.path:
        sys.path.insert(0, sp)


class FakeResponse:
    """Minimal stand-in for requests.Response usable in unit tests."""

    def __init__(self, status_code: int, json_data: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._json = json_data if json_data is not None else {}
        self.text = text or (str(self._json) if self._json else "")

    def json(self):
        return self._json

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}: {self.text}")


@pytest.fixture
def fake_response():
    """Factory fixture for building FakeResponse instances in tests."""
    return FakeResponse


@pytest.fixture
def mock_dataverse_client():
    """A MagicMock shaped like the shared DataverseClient.

    Preconfigured with:
      - api_url ending in '/'
      - dry_run = False
      - _get_headers returning a dict
      - _session as a MagicMock so .post / .patch / .get etc. are patchable
    """
    c = MagicMock()
    c.dry_run = False
    c.api_url = "https://contoso.crm.dynamics.com/api/data/v9.2/"
    c.environment_url = "https://contoso.crm.dynamics.com"
    c._get_headers = MagicMock(return_value={
        "Authorization": "Bearer fake.token",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        "Accept": "application/json",
        "Content-Type": "application/json; charset=utf-8",
    })
    c._session = MagicMock()
    return c
