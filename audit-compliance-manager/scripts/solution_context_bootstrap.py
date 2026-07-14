#!/usr/bin/env python3
"""
Dataverse solution-context bootstrap helpers for ACM schema and component writes.

Dataverse metadata/component write calls that include MSCRM.SolutionUniqueName
require the target unmanaged solution to already exist. This module ensures the
ACM publisher/solution shell exists before write calls attach that header.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable
from urllib.parse import urljoin

import requests


def _odata_literal(value: str) -> str:
    """Return an OData string literal with apostrophes escaped."""
    escaped = value.replace("'", "''")
    return f"'{escaped}'"


@dataclass(frozen=True)
class SolutionBootstrapConfig:
    """Configuration for Dataverse publisher/solution bootstrap."""

    publisher_unique_name: str = "FSIPublisher"
    publisher_friendly_name: str = "FSIPublisher"
    publisher_prefix: str = "fsi"
    publisher_option_value_prefix: int = 10000
    publisher_description: str = (
        "Publisher for the Audit Compliance Manager unmanaged solution shell."
    )
    solution_friendly_name: str = "Audit Compliance Manager"
    solution_version: str = "1.0.6.0"
    solution_description: str = (
        "Unmanaged shell that holds ACM Dataverse metadata and connection components."
    )


DEFAULT_SOLUTION_BOOTSTRAP_CONFIG = SolutionBootstrapConfig()


class SolutionContextBootstrapper:
    """Ensures publisher and unmanaged solution exist before solution-scoped writes."""

    _ENTITY_ID_PATTERNS = {
        "publishers": re.compile(r"publishers\(([0-9a-fA-F-]{36})\)", re.IGNORECASE),
        "solutions": re.compile(r"solutions\(([0-9a-fA-F-]{36})\)", re.IGNORECASE),
    }

    def __init__(
        self,
        *,
        session: requests.Session,
        api_url: str,
        get_headers: Callable[[], dict],
        solution_name: str,
        config: SolutionBootstrapConfig = DEFAULT_SOLUTION_BOOTSTRAP_CONFIG,
    ) -> None:
        self._session = session
        self._api_url = api_url
        self._get_headers = get_headers
        self._solution_name = solution_name
        self._config = config
        self._ready = False

    def ensure(self) -> None:
        """Create/reuse publisher and unmanaged solution for the configured name."""
        if self._ready or not self._solution_name:
            return

        solution = self._find_solution()
        if solution:
            self._ready = True
            return

        publisher = self._find_publisher()
        if not publisher:
            publisher = self._create_publisher()

        self._create_solution(publisher_id=publisher["publisherid"])
        self._ready = True

    def _find_publisher(self) -> dict | None:
        publisher_prefix = _odata_literal(self._config.publisher_prefix)
        publisher_name = _odata_literal(self._config.publisher_unique_name)
        response = self._session.get(
            urljoin(self._api_url, "publishers"),
            headers=self._get_headers(),
            params={
                "$select": (
                    "publisherid,uniquename,friendlyname,"
                    "customizationprefix,customizationoptionvalueprefix"
                ),
                "$filter": (
                    f"customizationprefix eq {publisher_prefix} "
                    f"or uniquename eq {publisher_name}"
                ),
            },
        )
        response.raise_for_status()
        records = response.json().get("value", [])
        if not records:
            return None

        for record in records:
            if (record.get("uniquename") or "").lower() == self._config.publisher_unique_name.lower():
                return record
        for record in records:
            if (record.get("customizationprefix") or "").lower() == self._config.publisher_prefix.lower():
                return record
        return records[0]

    def _create_publisher(self) -> dict:
        body = {
            "friendlyname": self._config.publisher_friendly_name,
            "uniquename": self._config.publisher_unique_name,
            "customizationprefix": self._config.publisher_prefix,
            "customizationoptionvalueprefix": self._config.publisher_option_value_prefix,
            "description": self._config.publisher_description,
        }
        response = self._session.post(
            urljoin(self._api_url, "publishers"),
            headers=self._get_headers(),
            json=body,
        )
        response.raise_for_status()

        publisher_id = self._parse_entity_id(response, "publishers")
        if not publisher_id:
            publisher = self._find_publisher()
            if not publisher:
                raise RuntimeError("Publisher creation succeeded but publisher lookup did not return a record.")
            return publisher

        return {
            "publisherid": publisher_id,
            "uniquename": self._config.publisher_unique_name,
            "friendlyname": self._config.publisher_friendly_name,
            "customizationprefix": self._config.publisher_prefix,
            "customizationoptionvalueprefix": self._config.publisher_option_value_prefix,
        }

    def _find_solution(self) -> dict | None:
        solution_name = _odata_literal(self._solution_name)
        response = self._session.get(
            urljoin(self._api_url, "solutions"),
            headers=self._get_headers(),
            params={
                "$select": "solutionid,uniquename,friendlyname,version",
                "$filter": f"uniquename eq {solution_name}",
            },
        )
        response.raise_for_status()
        values = response.json().get("value", [])
        return values[0] if values else None

    def _create_solution(self, *, publisher_id: str) -> None:
        body = {
            "friendlyname": self._config.solution_friendly_name,
            "uniquename": self._solution_name,
            "version": self._config.solution_version,
            "description": self._config.solution_description,
            "publisherid@odata.bind": f"/publishers({publisher_id})",
        }
        response = self._session.post(
            urljoin(self._api_url, "solutions"),
            headers=self._get_headers(),
            json=body,
        )
        response.raise_for_status()

    def _parse_entity_id(self, response: requests.Response, entity_set: str) -> str | None:
        entity_id = response.headers.get("OData-EntityId", "")
        if not entity_id:
            return None
        pattern = self._ENTITY_ID_PATTERNS.get(entity_set)
        if not pattern:
            return None
        match = pattern.search(entity_id)
        return match.group(1) if match else None
