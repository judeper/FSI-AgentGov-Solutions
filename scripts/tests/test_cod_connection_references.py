"""Offline regression checks for COD connection-reference setup."""

from __future__ import annotations

import ast
from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "credential-oversharing-detector"
    / "scripts"
    / "create_cod_connection_references.py"
)


class RecordingClient:
    """Record setup operations without loading authentication dependencies."""

    def __init__(self, *, existing: bool = False, dry_run: bool = False) -> None:
        self.existing = existing
        self.dry_run = dry_run
        self.created: list[tuple[str, dict]] = []
        self.queries: list[tuple[str, str]] = []

    def query(self, entity: str, *, filter_expr: str) -> list[dict]:
        """Record the lookup and optionally simulate an existing reference."""
        self.queries.append((entity, filter_expr))
        return [{"connectionreferenceid": "existing"}] if self.existing else []

    def create_record(self, entity: str, data: dict) -> None:
        """Capture exactly the payload that would be sent to Dataverse."""
        self.created.append((entity, data))


def _setup(client: RecordingClient, *, dry_run: bool = False) -> dict:
    tree = ast.parse(SCRIPT.read_text(encoding="utf-8"))
    nodes = [
        node
        for node in tree.body
        if (
            isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name) and target.id == "CONNECTION_REFS"
                for target in node.targets
            )
        )
        or (
            isinstance(node, ast.FunctionDef)
            and node.name == "create_connection_references"
        )
    ]
    namespace = {"DataverseClient": RecordingClient}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(SCRIPT), "exec"), namespace)
    return namespace["create_connection_references"](client, dry_run=dry_run)


def test_new_references_use_actual_v2_connector() -> None:
    """The V2-named reference must not point to the older admin connector."""
    client = RecordingClient()
    result = _setup(client)
    assert result == {"created": 4, "skipped": 0, "errors": 0}
    assert len(client.queries) == 4
    assert all(entity == "connectionreferences" for entity, _ in client.created)
    connectors = {
        data["connectionreferencelogicalname"]: data["connectorid"]
        for _, data in client.created
    }
    prefix = "/providers/Microsoft.PowerApps/apis/"
    assert connectors == {
        "fsi_cr_dataverse_credentialoversharing": prefix + "shared_commondataserviceforapps",
        "fsi_cr_teams_credentialoversharing": prefix + "shared_teams",
        "fsi_cr_approvals_credentialoversharing": prefix + "shared_approvals",
        "fsi_cr_powerplatformadminv2_credentialoversharing": prefix
        + "shared_powerplatformadminv2",
    }


def test_existing_references_are_not_silently_replaced() -> None:
    """Existing bindings keep the manual migration behavior documented."""
    client = RecordingClient(existing=True)
    assert _setup(client) == {"created": 0, "skipped": 4, "errors": 0}
    assert len(client.queries) == 4
    assert client.created == []


def test_dry_run_makes_no_dataverse_calls() -> None:
    """Both dry-run inputs must remain read/write-free."""
    for client_dry_run, argument_dry_run in ((True, False), (False, True)):
        client = RecordingClient(dry_run=client_dry_run)
        assert _setup(client, dry_run=argument_dry_run) == {
            "created": 4,
            "skipped": 0,
            "errors": 0,
        }
        assert client.queries == []
        assert client.created == []
