#!/usr/bin/env python3
"""Import Microsoft 365 Product Feedback CSV exports into Hallucination Tracker."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional, TextIO

SOURCE_MICROSOFT_365_COPILOT = 100000004

CATEGORY_FACTUAL_ERROR = 100000000
CATEGORY_FABRICATED_DATA = 100000001
CATEGORY_CITATION_MISSING = 100000002
CATEGORY_OUTDATED_INFO = 100000003
CATEGORY_CONFIDENCE_OVERSTATEMENT = 100000004

SEVERITY_LOW = 100000000
SEVERITY_MEDIUM = 100000001
SEVERITY_HIGH = 100000002
SEVERITY_CRITICAL = 100000003

CATEGORY_LABELS = {
    CATEGORY_FACTUAL_ERROR: "factual-error",
    CATEGORY_FABRICATED_DATA: "fabricated-data",
    CATEGORY_CITATION_MISSING: "citation-missing",
    CATEGORY_OUTDATED_INFO: "outdated-info",
    CATEGORY_CONFIDENCE_OVERSTATEMENT: "confidence-overstatement",
}
DEFAULT_CHANNEL_ID = "m365copilot"
MAX_TOPIC_NAME_LENGTH = 200
MAX_TOPIC_ID_LENGTH = 200
MAX_CHANNEL_ID_LENGTH = 100
MAX_CONVERSATION_ID_LENGTH = 200
MAX_CLUSTER_COMPONENT_LENGTH = 32

REQUIRED_HEADERS = ("App", "Comments", "Date Submitted", "Feedback Type")
CONTENT_SAMPLE_HEADERS = ("Prompt", "Generated Response")

NEGATIVE_SENTIMENT_MARKERS = (
    "thumbs down",
    "negative",
    "not helpful",
    "dislike",
    "issue",
    "problem",
    "bug",
)
POSITIVE_SENTIMENT_MARKERS = (
    "thumbs up",
    "positive",
    "helpful",
    "like",
    "praise",
)
NEGATIVE_COMMENT_MARKERS = (
    "incorrect",
    "inaccurate",
    "wrong",
    "not useful",
    "not helpful",
    "unsupported",
    "citation",
    "source",
    "hallucinat",
    "made up",
    "fabricated",
    "fake",
    "outdated",
    "stale",
    "obsolete",
    "misleading",
    "error",
    "issue",
    "problem",
    "failed",
    "missing",
)
POSITIVE_COMMENT_MARKERS = (
    "great",
    "helpful",
    "useful",
    "good",
    "love",
    "thanks",
    "accurate",
)
CITATION_KEYWORDS = ("citation", "source", "reference", "link", "unsupported", "no source")
OUTDATED_KEYWORDS = ("outdated", "stale", "obsolete", "old policy", "last year", "no longer current")
FABRICATED_KEYWORDS = ("made up", "fabricated", "invented", "fake", "not real", "nonexistent")
CONFIDENCE_KEYWORDS = ("definitely", "guaranteed", "certain", "stated as fact", "overconfident")
CRITICAL_KEYWORDS = ("regulatory", "compliance", "customer harm", "financial loss", "legal risk")


@dataclass
class ImportSummary:
    rows_read: int = 0
    rows_normalized: int = 0
    rows_written: int = 0
    rows_skipped: int = 0
    skipped_reasons: Counter = field(default_factory=Counter)
    normalized_records: list[dict[str, Any]] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def skip(self, reason: str) -> None:
        self.rows_skipped += 1
        self.skipped_reasons[reason] += 1


class DataverseRecordWriter:
    """Thin Dataverse writer wrapper used by the importer."""

    def __init__(self, client: Any):
        self.client = client

    def existing_reportnames(self, reportnames: Iterable[str]) -> set[str]:
        existing: set[str] = set()
        unique_names = sorted(set(reportnames))
        if not unique_names:
            return existing

        for chunk in chunked(unique_names, 20):
            names_filter = " or ".join(
                f"fsi_reportname eq '{escape_odata_string(name)}'" for name in chunk
            )
            rows = self.client.query(
                "fsi_hallucinationreports",
                select=["fsi_reportname"],
                filter_expr=(
                    f"fsi_source eq {SOURCE_MICROSOFT_365_COPILOT} and ({names_filter})"
                ),
            )
            existing.update(
                row["fsi_reportname"] for row in rows if row.get("fsi_reportname")
            )
        return existing

    def create(self, record: dict[str, Any]) -> str:
        return self.client.create_record("fsi_hallucinationreports", record)


def normalize_header_name(value: str) -> str:
    return " ".join(value.replace("\ufeff", "").replace("_", " ").strip().split()).casefold()


def build_header_aliases() -> dict[str, str]:
    aliases: dict[str, str] = {}
    canonical_groups = {
        "App": ("product", "application"),
        "Comments": (
            "comment",
            "feedback text",
            "feedback details",
            "description",
        ),
        "Date Submitted": (
            "submission date",
            "submission date/time",
            "submitted at",
            "timestamp",
        ),
        "Feedback Type": ("type", "feedback category"),
        "Sentiment": (
            "reaction",
            "thumbs",
            "rating",
            "was this helpful",
            "helpful",
        ),
        "User Id": ("user identifier", "user principal name", "upn", "user id / email"),
        "User Email": ("email",),
        "Language or Comment Language": ("comment language", "language"),
        "Channel": ("app channel",),
        "Feature Area": ("feature", "area"),
        "App Build": ("build", "copilot version"),
        "App Language": ("product language",),
        "Attachments": ("has attachments",),
        "TenantId": ("tenant id",),
        "App module": ("module",),
        "Survey Questions": ("survey question",),
        "Survey Responses": (
            "survey response",
            "question response",
            "response value",
        ),
        "Feedback Id": (
            "feedbackid",
            "session id",
            "sessionid",
            "conversation id",
            "conversationid",
        ),
        "Prompt": ("scenario/prompt", "scenario", "prompt text"),
        "Generated Response": (
            "response",
            "copilot response",
            "agent response",
        ),
        "Agent ID": ("agentid",),
        "Agent Name": ("agentname",),
    }
    for canonical, variants in canonical_groups.items():
        aliases[normalize_header_name(canonical)] = canonical
        for variant in variants:
            aliases[normalize_header_name(variant)] = canonical
    return aliases


HEADER_ALIASES = build_header_aliases()


def chunked(items: list[str], chunk_size: int) -> list[list[str]]:
    return [items[index:index + chunk_size] for index in range(0, len(items), chunk_size)]


def escape_odata_string(value: str) -> str:
    return value.replace("'", "''")


def canonicalize_row(raw_row: dict[str, Optional[str]]) -> dict[str, str]:
    canonical_row: dict[str, str] = {}
    for header, value in raw_row.items():
        if header is None:
            continue
        canonical_header = HEADER_ALIASES.get(normalize_header_name(header), header.strip())
        text = (value or "").strip()
        if canonical_header not in canonical_row or (text and not canonical_row[canonical_header]):
            canonical_row[canonical_header] = text
    return canonical_row


def validate_headers(fieldnames: list[str]) -> None:
    canonical_headers = {
        HEADER_ALIASES.get(normalize_header_name(name), name.strip())
        for name in fieldnames
    }
    missing = [header for header in REQUIRED_HEADERS if header not in canonical_headers]
    if missing:
        raise ValueError(
            "Missing required CSV columns: " + ", ".join(missing)
        )


def load_product_feedback_rows(input_path: Path) -> list[tuple[int, dict[str, str]]]:
    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV file is missing a header row.")
        validate_headers(reader.fieldnames)
        return [
            (row_number, canonicalize_row(row))
            for row_number, row in enumerate(reader, start=2)
        ]


def get_value(row: dict[str, str], *headers: str) -> str:
    for header in headers:
        value = row.get(header, "").strip()
        if value:
            return value
    return ""


def limit_length(value: str, max_length: int) -> str:
    return value if len(value) <= max_length else value[:max_length]


def normalize_cluster_text(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


def slugify_identifier(
    value: str,
    *,
    fallback: str,
    max_length: int = MAX_CLUSTER_COMPONENT_LENGTH,
) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-")
    if not slug:
        slug = fallback
    return limit_length(slug, max_length)


def build_feedback_comment(row: dict[str, str]) -> str:
    for header in ("Comments", "Survey Responses", "Feedback Type"):
        value = get_value(row, header)
        if value:
            return value
    return ""


def build_topic_name(row: dict[str, str]) -> str:
    app = get_value(row, "App")
    app_key = normalize_cluster_text(app)
    qualifiers: list[str] = []
    for header in ("Feature Area", "App module"):
        value = get_value(row, header)
        if not value:
            continue
        if normalize_cluster_text(value) == app_key or value in qualifiers:
            continue
        qualifiers.append(value)
    if qualifiers:
        return limit_length(f"{app} / {' / '.join(qualifiers)}", MAX_TOPIC_NAME_LENGTH)
    return limit_length(app, MAX_TOPIC_NAME_LENGTH)


def build_channel_id(row: dict[str, str]) -> str:
    raw_channel = get_value(row, "Channel")
    if not raw_channel:
        return DEFAULT_CHANNEL_ID
    return slugify_identifier(
        raw_channel,
        fallback=DEFAULT_CHANNEL_ID,
        max_length=MAX_CHANNEL_ID_LENGTH,
    )


def build_cluster_signal(row: dict[str, str]) -> str:
    parts = [
        normalize_cluster_text(get_value(row, header))
        for header in ("Comments", "Survey Responses")
        if get_value(row, header)
    ]
    return " ".join(part for part in parts if part)


def build_cluster_topic_id(
    row: dict[str, str],
    *,
    reportname: str,
    category: int,
    channel_id: str,
) -> str:
    app_key = slugify_identifier(get_value(row, "App"), fallback="app")
    feature_key = slugify_identifier(
        get_value(row, "Feature Area", "App module"),
        fallback="general",
    )
    channel_key = slugify_identifier(channel_id, fallback=DEFAULT_CHANNEL_ID)
    category_key = CATEGORY_LABELS.get(category, "uncategorized")
    signal = build_cluster_signal(row)
    if signal:
        signal_key = slugify_identifier(
            " ".join(signal.split()[:6]),
            fallback="signal",
            max_length=48,
        )
        digest_basis = "|".join((app_key, feature_key, channel_key, category_key, signal))
        digest = hashlib.sha256(digest_basis.encode("utf-8")).hexdigest()[:12]
        cluster_id = (
            f"m365pf-{app_key}-{feature_key}-{channel_key}-"
            f"{category_key}-{signal_key}-{digest}"
        )
    else:
        fallback_source = get_value(row, "Feedback Id") or reportname
        digest_basis = "|".join(
            (app_key, feature_key, channel_key, category_key, fallback_source)
        )
        digest = hashlib.sha256(digest_basis.encode("utf-8")).hexdigest()[:12]
        cluster_id = (
            f"m365pf-{app_key}-{feature_key}-{channel_key}-"
            f"{category_key}-record-{digest}"
        )
    return limit_length(cluster_id, MAX_TOPIC_ID_LENGTH)


def parse_submitted_at(value: str) -> Optional[str]:
    if not value:
        return None

    normalized = value.strip()
    candidates = [
        normalized,
        normalized.replace("Z", "+00:00"),
    ]
    formats = (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%Y %I:%M:%S %p",
        "%m/%d/%Y %I:%M %p",
    )

    for candidate in candidates:
        try:
            parsed = datetime.fromisoformat(candidate)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        except ValueError:
            pass

    for date_format in formats:
        try:
            parsed = datetime.strptime(normalized, date_format)
            parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        except ValueError:
            continue

    return None


def is_negative_feedback(row: dict[str, str]) -> bool:
    sentiment_text = " ".join(
        value
        for value in (
            get_value(row, "Sentiment"),
            get_value(row, "Feedback Type"),
            get_value(row, "Survey Responses"),
        )
        if value
    ).casefold()
    if any(marker in sentiment_text for marker in NEGATIVE_SENTIMENT_MARKERS):
        return True
    if any(marker in sentiment_text for marker in POSITIVE_SENTIMENT_MARKERS):
        return False

    comment = get_value(row, "Comments").casefold()
    if not comment:
        return False
    if any(marker in comment for marker in NEGATIVE_COMMENT_MARKERS):
        return True
    if any(marker in comment for marker in POSITIVE_COMMENT_MARKERS):
        return False
    return True


def classify_category(row: dict[str, str]) -> int:
    text = " ".join(
        value.casefold()
        for value in (
            get_value(row, "Comments"),
            get_value(row, "Survey Responses"),
        )
        if value
    )
    if any(keyword in text for keyword in OUTDATED_KEYWORDS):
        return CATEGORY_OUTDATED_INFO
    if any(keyword in text for keyword in CITATION_KEYWORDS):
        return CATEGORY_CITATION_MISSING
    if any(keyword in text for keyword in FABRICATED_KEYWORDS):
        return CATEGORY_FABRICATED_DATA
    if any(keyword in text for keyword in CONFIDENCE_KEYWORDS):
        return CATEGORY_CONFIDENCE_OVERSTATEMENT
    return CATEGORY_FACTUAL_ERROR


def classify_severity(row: dict[str, str], category: int) -> int:
    text = " ".join(
        value.casefold()
        for value in (
            get_value(row, "Comments"),
            get_value(row, "Survey Responses"),
        )
        if value
    )
    if any(keyword in text for keyword in CRITICAL_KEYWORDS):
        return SEVERITY_CRITICAL
    if category in {CATEGORY_OUTDATED_INFO, CATEGORY_CONFIDENCE_OVERSTATEMENT}:
        return SEVERITY_MEDIUM
    if not text:
        return SEVERITY_LOW
    return SEVERITY_HIGH


def build_description(row: dict[str, str]) -> str:
    details = []
    for header in (
        "App",
        "Feedback Type",
        "Sentiment",
        "Language or Comment Language",
        "Channel",
        "Feature Area",
        "App Build",
        "App Language",
        "Attachments",
        "TenantId",
        "App module",
        "Survey Questions",
        "Survey Responses",
        "Feedback Id",
    ):
        value = get_value(row, header)
        if value:
            details.append(f"{header}: {value}")
    return " | ".join(details)


def build_reportname(row: dict[str, str], reported_at: str) -> str:
    fingerprint_source = json.dumps(
        {
            "app": get_value(row, "App"),
            "comments": get_value(row, "Comments"),
            "date_submitted": reported_at,
            "feedback_id": get_value(row, "Feedback Id"),
            "feedback_type": get_value(row, "Feedback Type"),
            "sentiment": get_value(row, "Sentiment"),
            "user_email": get_value(row, "User Email"),
            "user_id": get_value(row, "User Id"),
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    digest = hashlib.sha256(fingerprint_source.encode("utf-8")).hexdigest()[:16]
    day_component = reported_at[:10].replace("-", "") if reported_at else "undated"
    return f"HT-M365PF-{day_component}-{digest}"


def normalize_feedback_row(
    row: dict[str, str],
    *,
    include_content_samples: bool = False,
) -> tuple[Optional[dict[str, Any]], Optional[str], bool]:
    app = get_value(row, "App")
    if not app:
        return None, "missing_app", False

    if not get_value(row, "Feedback Type"):
        return None, "missing_feedback_type", False

    reported_at = parse_submitted_at(get_value(row, "Date Submitted"))
    if not reported_at:
        return None, "invalid_date", False

    if not is_negative_feedback(row):
        return None, "not_negative_feedback", False

    content_sample_present = any(get_value(row, header) for header in CONTENT_SAMPLE_HEADERS)
    category = classify_category(row)
    severity = classify_severity(row, category)
    reportname = build_reportname(row, reported_at)
    channel_id = build_channel_id(row)
    record: dict[str, Any] = {
        "fsi_reportname": reportname,
        "fsi_category": category,
        "fsi_severity": severity,
        "fsi_source": SOURCE_MICROSOFT_365_COPILOT,
        "fsi_topicname": build_topic_name(row),
        "fsi_topicid": build_cluster_topic_id(
            row,
            reportname=reportname,
            category=category,
            channel_id=channel_id,
        ),
        "fsi_channelid": channel_id,
        "fsi_feedbackcomment": build_feedback_comment(row),
        "fsi_reportedat": reported_at,
        "fsi_conversationid": limit_length(
            get_value(row, "Feedback Id") or reportname,
            MAX_CONVERSATION_ID_LENGTH,
        ),
    }

    description = build_description(row)
    if description:
        record["fsi_description"] = description

    reported_by = get_value(row, "User Email", "User Id")
    if reported_by:
        record["fsi_reportedby"] = reported_by

    agent_id = get_value(row, "Agent ID")
    if agent_id:
        record["fsi_agentid"] = agent_id

    agent_name = get_value(row, "Agent Name")
    if agent_name:
        record["fsi_agentname"] = agent_name

    if include_content_samples:
        prompt = get_value(row, "Prompt")
        if prompt:
            record["fsi_userquery"] = prompt
        response = get_value(row, "Generated Response")
        if response:
            record["fsi_agentresponse"] = response

    return record, None, content_sample_present


def write_preview_json(output_path: Path, records: list[dict[str, Any]]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(records, ensure_ascii=False, indent=2, sort_keys=True)
    output_path.write_text(payload + "\n", encoding="utf-8")


def process_product_feedback_csv(
    input_path: Path,
    *,
    output_path: Optional[Path] = None,
    writer: Optional[Any] = None,
    dry_run: bool = False,
    include_content_samples: bool = False,
    verbose: bool = False,
    log_stream: TextIO = sys.stderr,
) -> ImportSummary:
    summary = ImportSummary()
    rows = load_product_feedback_rows(input_path)
    seen_reportnames: set[str] = set()
    content_sample_seen = False

    for row_number, row in rows:
        summary.rows_read += 1
        record, skip_reason, content_sample_present = normalize_feedback_row(
            row,
            include_content_samples=include_content_samples,
        )
        content_sample_seen = content_sample_seen or content_sample_present
        if record is None:
            summary.skip(skip_reason or "skipped")
            if verbose:
                print(f"Skipping row {row_number}: {skip_reason}", file=log_stream)
            continue
        if record["fsi_reportname"] in seen_reportnames:
            summary.skip("duplicate_row")
            if verbose:
                print(
                    f"Skipping row {row_number}: duplicate_row ({record['fsi_reportname']})",
                    file=log_stream,
                )
            continue
        seen_reportnames.add(record["fsi_reportname"])
        summary.rows_normalized += 1
        summary.normalized_records.append(record)

    summary.normalized_records.sort(key=lambda item: item["fsi_reportname"])

    if content_sample_seen and not include_content_samples:
        summary.warnings.append(
            "Prompt/response content samples were present but not imported. "
            "Re-run with --include-content-samples only after privacy review."
        )

    if output_path is not None:
        write_preview_json(output_path, summary.normalized_records)

    if writer is not None and not dry_run:
        existing = writer.existing_reportnames(
            record["fsi_reportname"] for record in summary.normalized_records
        )
        for record in summary.normalized_records:
            if record["fsi_reportname"] in existing:
                summary.skip("already_exists")
                if verbose:
                    print(
                        f"Skipping existing Dataverse row: {record['fsi_reportname']}",
                        file=log_stream,
                    )
                continue
            writer.create(record)
            summary.rows_written += 1
            existing.add(record["fsi_reportname"])

    return summary


def render_summary(
    summary: ImportSummary,
    *,
    output_path: Optional[Path],
    target_dataverse: bool,
    dry_run: bool,
) -> str:
    lines = [
        "Microsoft 365 Product Feedback import summary",
        f"Rows read: {summary.rows_read}",
        f"Rows normalized: {summary.rows_normalized}",
        f"Rows skipped: {summary.rows_skipped}",
    ]
    if output_path is not None:
        lines.append(f"Preview JSON: {output_path}")
    if target_dataverse:
        if dry_run:
            lines.append(
                "Dataverse writes skipped because --dry-run was supplied; preview the normalized rows before rerunning."
            )
        else:
            lines.append(f"Rows written to Dataverse: {summary.rows_written}")
    if summary.skipped_reasons:
        lines.append(
            "Skip reasons: "
            + ", ".join(
                f"{reason}={count}"
                for reason, count in sorted(summary.skipped_reasons.items())
            )
        )
    if summary.warnings:
        lines.append("Warnings: " + " | ".join(summary.warnings))
    return "\n".join(lines)


def resolve_auth_mode(args: argparse.Namespace) -> str:
    if args.auth_mode:
        return args.auth_mode
    if args.interactive:
        return "interactive"
    if os.environ.get("AZURE_FEDERATED_TOKEN_FILE") and args.tenant_id and args.client_id:
        return "workload-identity"
    if args.client_secret:
        return "client-secret"
    return "managed-identity"


def create_dataverse_writer(args: argparse.Namespace) -> DataverseRecordWriter:
    shared_path = Path(__file__).resolve().parents[2] / "scripts" / "shared"
    if str(shared_path) not in sys.path:
        sys.path.insert(0, str(shared_path))
    try:
        from dataverse_client import DataverseClient
    except ImportError as exc:  # pragma: no cover - depends on local env
        raise RuntimeError(
            "Failed to import the shared Dataverse client. Install dependencies with "
            "pip install -r hallucination-tracker/scripts/requirements.txt"
        ) from exc

    client = DataverseClient(
        tenant_id=args.tenant_id,
        environment_url=args.environment_url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=args.interactive,
        dry_run=args.dry_run,
        auth_mode=resolve_auth_mode(args),
    )
    return DataverseRecordWriter(client)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Normalize Microsoft 365 Product Feedback CSV exports for the "
            "Hallucination Tracker Dataverse schema."
        )
    )
    parser.add_argument("--input", required=True, help="Path to the exported Product Feedback CSV file.")
    parser.add_argument(
        "--output",
        required=True,
        help="Use 'dataverse' to write to Dataverse, or provide a JSON file path for normalized preview output.",
    )
    parser.add_argument(
        "--environment-url",
        "--environment",
        dest="environment_url",
        help="Dataverse environment URL (required when --output dataverse is used without --dry-run).",
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("HT_TENANT_ID") or os.environ.get("AZURE_TENANT_ID"),
        help="Microsoft Entra tenant ID for Dataverse authentication.",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("HT_CLIENT_ID") or os.environ.get("AZURE_CLIENT_ID"),
        help="Application or managed-identity client ID for Dataverse authentication.",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("HT_CLIENT_SECRET") or os.environ.get("AZURE_CLIENT_SECRET"),
        help="Legacy dev-only client secret for Dataverse authentication.",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication for Dataverse writes.",
    )
    parser.add_argument(
        "--auth-mode",
        choices=["interactive", "managed-identity", "workload-identity", "client-secret"],
        help="Explicit Dataverse authentication mode.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and normalize rows without writing to Dataverse.",
    )
    parser.add_argument(
        "--include-content-samples",
        action="store_true",
        help="Import prompt/response content sample columns after tenant privacy review.",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Log skipped rows and duplicate decisions.")

    args = parser.parse_args(argv)
    target_dataverse = args.output.casefold() == "dataverse"
    if target_dataverse and not args.environment_url and not args.dry_run:
        parser.error("--environment-url is required when --output dataverse is used without --dry-run.")
    return args


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    input_path = Path(args.input)
    output_path = None if args.output.casefold() == "dataverse" else Path(args.output)
    writer = None
    if args.output.casefold() == "dataverse" and not args.dry_run:
        writer = create_dataverse_writer(args)

    try:
        summary = process_product_feedback_csv(
            input_path,
            output_path=output_path,
            writer=writer,
            dry_run=args.dry_run,
            include_content_samples=args.include_content_samples,
            verbose=args.verbose,
        )
    except FileNotFoundError:
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive CLI path
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(
        render_summary(
            summary,
            output_path=output_path,
            target_dataverse=args.output.casefold() == "dataverse",
            dry_run=args.dry_run,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
