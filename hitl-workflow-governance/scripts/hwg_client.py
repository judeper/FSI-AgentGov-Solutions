#!/usr/bin/env python3
"""HWGClient - DEPRECATED Dataverse Web API client stub.

.. deprecated:: 1.1.2
    This module is deprecated since v1.1.2. Use the shared DataverseClient
    (see CHANGELOG.md) which is imported by all create_hwg_*.py scripts and
    deploy.py.

This file is retained solely for backward compatibility. It emits a
DeprecationWarning on import and re-exports nothing. Migrate all callers
to the shared DataverseClient at ``../../scripts/shared/dataverse_client.py``.
"""

import warnings

warnings.warn(
    "hwg_client.HWGClient is deprecated since v1.1.2. "
    "Use the shared DataverseClient (see CHANGELOG.md), "
    "which replaced this module in v1.1.2.",
    DeprecationWarning,
    stacklevel=2,
)

raise ImportError(
    "hwg_client has been removed. Use the shared DataverseClient instead. "
    "See CHANGELOG.md for migration details."
)
