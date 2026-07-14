"""Guards for Dataverse global option-set metadata discriminators in ACM."""

from __future__ import annotations

import ast
from pathlib import Path

SOLUTION_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = SOLUTION_ROOT / "scripts"

OPTIONSET_ROOT_TYPE = "Microsoft.Dynamics.CRM.OptionSetMetadata"
OPTION_VALUE_TYPE = "Microsoft.Dynamics.CRM.OptionMetadata"

SCHEMA_FILES = (
    SCRIPTS_DIR / "create_dataverse_schema.py",
    SCRIPTS_DIR / "create_audit_compliance_schema.py",
)
CLIENT_FILES = (
    SCRIPTS_DIR / "acv_client.py",
    SCRIPTS_DIR / "alca_client.py",
)


def _get_function_node(path: Path, function_name: str) -> ast.FunctionDef:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == function_name:
            return node
    raise AssertionError(f"{path.name} is missing function {function_name!r}")


def _get_optionsets_literal(path: Path) -> dict[str, dict]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "OPTIONSETS":
                    value = ast.literal_eval(node.value)
                    if not isinstance(value, dict):
                        raise AssertionError(f"{path.name} OPTIONSETS must be a dict")
                    return value
    raise AssertionError(f"{path.name} is missing OPTIONSETS assignment")


def test_schema_optionsets_include_required_discriminators() -> None:
    for schema_file in SCHEMA_FILES:
        optionsets = _get_optionsets_literal(schema_file)
        assert optionsets, f"{schema_file.name} OPTIONSETS should not be empty"

        for optionset_name, optionset in optionsets.items():
            assert optionset.get("@odata.type") == OPTIONSET_ROOT_TYPE, (
                f"{schema_file.name}:{optionset_name} missing root "
                f"@odata.type={OPTIONSET_ROOT_TYPE}"
            )

            options = optionset.get("Options")
            assert isinstance(options, list) and options, (
                f"{schema_file.name}:{optionset_name} should define at least one option"
            )

            for index, option in enumerate(options):
                assert option.get("@odata.type") == OPTION_VALUE_TYPE, (
                    f"{schema_file.name}:{optionset_name} option[{index}] missing "
                    f"@odata.type={OPTION_VALUE_TYPE}"
                )


def test_clients_post_optionset_payload_without_rewriting_json_keyword() -> None:
    for client_file in CLIENT_FILES:
        func = _get_function_node(client_file, "create_global_optionset")

        posts_optionset_payload = False
        for node in ast.walk(func):
            if not isinstance(node, ast.Call):
                continue
            if not isinstance(node.func, ast.Attribute) or node.func.attr != "post":
                continue

            for keyword in node.keywords:
                if (
                    keyword.arg == "json"
                    and isinstance(keyword.value, ast.Name)
                    and keyword.value.id == "optionset_metadata"
                ):
                    posts_optionset_payload = True
                    break
            if posts_optionset_payload:
                break

        assert posts_optionset_payload, (
            f"{client_file.name}.create_global_optionset should post with "
            "json=optionset_metadata so metadata discriminators are preserved."
        )
