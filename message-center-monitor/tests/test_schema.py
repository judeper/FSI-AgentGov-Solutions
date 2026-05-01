"""Unit tests for create_mcm_dataverse_schema.py create_keys() (alternate-key
provisioning).

Covers the new code added in v2.4.0:
  - Alternate key payload shape (EntityKeyMetadata with KeyAttributes)
  - Idempotent on HTTP 412 PreconditionFailed
  - Idempotent on DuplicateRecord error code (or "duplicate"/"already exists" in message)
  - Honors --dry-run (no HTTP calls made)
  - URL targets EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys

The shared DataverseClient is mocked via the conftest.py mock_dataverse_client
fixture; we never make real network calls.
"""
from __future__ import annotations

import pytest

# create_mcm_dataverse_schema lives at message-center-monitor/scripts/. The
# conftest.py adds that directory to sys.path so this import works.
import create_mcm_dataverse_schema as schema_mod


class TestCreateKeysSuccess:
    def test_creates_alternate_key_when_missing(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(204)
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert result == {"created": 1, "skipped": 0}
        assert mock_dataverse_client._session.post.called

    def test_url_targets_entity_definitions_keys_collection(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(201)
        schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        url_arg = mock_dataverse_client._session.post.call_args.args[0]
        assert "EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys" in url_arg
        assert url_arg.startswith(mock_dataverse_client.api_url)

    def test_payload_has_correct_metadata_shape(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(204)
        schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        body = mock_dataverse_client._session.post.call_args.kwargs["json"]
        assert body["@odata.type"] == "Microsoft.Dynamics.CRM.EntityKeyMetadata"
        assert body["SchemaName"] == "fsi_MessageCenterIdKey"
        assert body["KeyAttributes"] == ["fsi_messagecenterid"]

    def test_sends_authorization_headers(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(204)
        schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        headers = mock_dataverse_client._session.post.call_args.kwargs["headers"]
        assert "Authorization" in headers


class TestCreateKeysIdempotency:
    def test_412_precondition_failed_is_treated_as_already_exists(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(412)
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert result == {"created": 0, "skipped": 1}

    def test_duplicate_record_error_code_is_treated_as_already_exists(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(
            500,
            json_data={"error": {"code": "DuplicateRecordWithUpdateConcurrency", "message": "Key already exists"}},
        )
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert result == {"created": 0, "skipped": 1}

    def test_duplicate_message_substring_is_treated_as_already_exists(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(
            400,
            json_data={"error": {"code": "0x80060808", "message": "An entity with this duplicate key cannot be created"}},
        )
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert result == {"created": 0, "skipped": 1}

    def test_already_exists_message_substring_is_treated_as_already_exists(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(
            400,
            json_data={"error": {"code": "0x123", "message": "The alternate key already exists for this entity."}},
        )
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert result == {"created": 0, "skipped": 1}


class TestCreateKeysDryRun:
    def test_dry_run_makes_no_http_calls(self, mock_dataverse_client):
        mock_dataverse_client.dry_run = True
        result = schema_mod.create_keys(mock_dataverse_client, dry_run=True)
        assert result == {"created": 1, "skipped": 0}
        assert not mock_dataverse_client._session.post.called

    def test_dry_run_with_module_argument_false_still_short_circuits_when_client_dry(
        self, mock_dataverse_client
    ):
        # The function checks client.dry_run, not the dry_run parameter.
        # This test pins that contract so a future refactor doesn't silently
        # send live traffic when only the parameter is False.
        mock_dataverse_client.dry_run = True
        schema_mod.create_keys(mock_dataverse_client, dry_run=False)
        assert not mock_dataverse_client._session.post.called


class TestCreateKeysHardFailures:
    def test_unrecoverable_5xx_raises(self, mock_dataverse_client, fake_response):
        # Plain 500 with no DuplicateRecord/duplicate/already-exists indicators
        # must propagate via raise_for_status.
        mock_dataverse_client._session.post.return_value = fake_response(
            500, json_data={"error": {"code": "InternalServerError", "message": "Service unavailable"}}
        )
        with pytest.raises(RuntimeError, match="HTTP 500"):
            schema_mod.create_keys(mock_dataverse_client, dry_run=False)

    def test_403_forbidden_raises(self, mock_dataverse_client, fake_response):
        mock_dataverse_client._session.post.return_value = fake_response(
            403, json_data={"error": {"code": "Forbidden", "message": "Caller is not authorized"}}
        )
        with pytest.raises(RuntimeError, match="HTTP 403"):
            schema_mod.create_keys(mock_dataverse_client, dry_run=False)


class TestAlternateKeysDeclaration:
    def test_message_center_key_is_declared(self):
        keys = [k for k in schema_mod.ALTERNATE_KEYS if k["table_logical"] == "fsi_messagecenterlog"]
        assert len(keys) == 1
        meta = keys[0]["metadata"]
        assert meta["SchemaName"] == "fsi_MessageCenterIdKey"
        assert meta["KeyAttributes"] == ["fsi_messagecenterid"]
        assert meta["@odata.type"] == "Microsoft.Dynamics.CRM.EntityKeyMetadata"
