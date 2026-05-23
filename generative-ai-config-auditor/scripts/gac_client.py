#!/usr/bin/env python3
"""GACClient - DEPRECATED Dataverse Web API client stub.

.. deprecated:: 1.2.1
    This module is deprecated since v1.2.1. Use the shared DataverseClient
    (see CHANGELOG.md) which is imported by all create_*.py and deploy.py
    scripts.

This file is retained solely for backward compatibility. It emits a
DeprecationWarning on import and re-exports nothing. Migrate all callers
to the shared DataverseClient at ``../scripts/shared/dataverse_client.py``.
"""

import warnings

warnings.warn(
    "gac_client.GACClient is deprecated since v1.2.1. "
    "Use the shared DataverseClient (see CHANGELOG.md), "
    "which replaced this module in v1.2.1.",
    DeprecationWarning,
    stacklevel=2,
)

raise ImportError(
    "gac_client has been removed. Use the shared DataverseClient instead. "
    "See CHANGELOG.md for migration details."
)
