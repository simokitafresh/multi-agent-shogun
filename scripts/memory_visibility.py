#!/usr/bin/env python3
"""Shared visibility contract for targeted three-layer memory searches."""


def targeted_event_visibility_clause(alias: str = "e") -> str:
    """SQL predicate for universal/document plus one bound directed target."""
    return (
        f"AND ({alias}.target = '' OR {alias}.target IS NULL "
        f"OR {alias}.target = ? OR {alias}.event_type = 'document')"
    )
