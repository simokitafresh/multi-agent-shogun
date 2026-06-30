"""Model label to stable analytics family helpers."""

import re

FAMILY_OPUS_46 = "opus_4_6"
FAMILY_OPUS_48 = "opus_4_8"
FAMILY_GPT_5 = "gpt_5"
FAMILY_CODEX = "codex"
FAMILY_HAIKU = "haiku"
FAMILY_OPUS = "opus"
FAMILY_SONNET = "sonnet"
FAMILY_UNKNOWN = "unknown"


def model_slug(model_label: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", str(model_label).lower()).strip("_")
    return slug or FAMILY_UNKNOWN


def extract_model_family(label: str) -> str:
    low = str(label).lower().replace("-", " ").replace("_", " ")
    if "opus" in low and ("4.8" in low or "4 8" in low):
        return FAMILY_OPUS_48
    if "opus" in low and ("4.6" in low or "4 6" in low):
        return FAMILY_OPUS_46
    if ("gpt" in low or "codex" in low) and (
        "5.4" in low or "5 4" in low or "5.5" in low or "5 5" in low
    ):
        return FAMILY_GPT_5
    if "sonnet" in low:
        return FAMILY_SONNET
    if "haiku" in low:
        return FAMILY_HAIKU
    if "opus" in low:
        return FAMILY_OPUS
    return model_slug(low)


def model_display_group(label: str) -> str:
    family = extract_model_family(label)
    if family == FAMILY_GPT_5 or family == FAMILY_CODEX or family.startswith("gpt"):
        return "Codex"
    if family == FAMILY_HAIKU:
        return "Haiku"
    if family == FAMILY_SONNET:
        return "Sonnet"
    if family in (FAMILY_OPUS, FAMILY_OPUS_46):
        return "Opus"
    return "Claude"
