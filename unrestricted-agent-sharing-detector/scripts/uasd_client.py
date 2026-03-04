#!/usr/bin/env python3
"""UASDClient - DEPRECATED Dataverse Web API client stub.

.. deprecated:: 1.0.1
    This module is deprecated since v1.0.1. Use the shared DataverseClient
    (see CHANGELOG.md) which is imported by all create_uasd_*.py scripts.

This file is retained solely for backward compatibility. It emits a
DeprecationWarning on import and re-exports nothing. Migrate all callers
to the shared DataverseClient at ``../scripts/shared/dataverse_client.py``.
"""

import warnings

warnings.warn(
    "uasd_client.UASDClient is deprecated since v1.0.1. "
    "Use the shared DataverseClient (see CHANGELOG.md), "
    "which replaced this module in v1.0.1.",
    DeprecationWarning,
    stacklevel=2,
)

raise ImportError(
    "uasd_client has been removed. Use the shared DataverseClient instead. "
    "See CHANGELOG.md for migration details."
)
