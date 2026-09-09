#!/usr/bin/env sh
set -eu

API_URL="https://api.normahub.cc/api/v1/public/models"
BASE_URL="https://api.normahub.cc/v1"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_DIR/config.toml"
CATALOG_FILE="$CODEX_DIR/normahub-models.json"

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "Error: curl is required." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' "Error: python3 is required." >&2
  exit 1
fi

printf 'NormaHub API key: '
stty -echo 2>/dev/null || true
IFS= read -r NORMAHUB_KEY
stty echo 2>/dev/null || true
printf '\n'

if [ -z "$NORMAHUB_KEY" ]; then
  printf '%s\n' "Error: API key cannot be empty." >&2
  exit 1
fi

mkdir -p "$CODEX_DIR"
chmod 700 "$CODEX_DIR" 2>/dev/null || true
TMP_MODELS=$(mktemp "${TMPDIR:-/tmp}/normahub-models.XXXXXX")
trap 'rm -f "$TMP_MODELS"' EXIT HUP INT TERM

if ! curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$API_URL" -o "$TMP_MODELS"; then
  printf '%s\n' "Error: failed to download $API_URL" >&2
  exit 1
fi

NORMAHUB_KEY="$NORMAHUB_KEY" CONFIG_FILE="$CONFIG_FILE" CATALOG_FILE="$CATALOG_FILE" \
  TMP_MODELS="$TMP_MODELS" BASE_URL="$BASE_URL" python3 <<'PY'
import json
import os
import re
from pathlib import Path

config_file = Path(os.environ["CONFIG_FILE"])
catalog_file = Path(os.environ["CATALOG_FILE"])

with open(os.environ["TMP_MODELS"], encoding="utf-8") as source:
    payload = json.load(source)

items = payload.get("models")
if not isinstance(items, list) or not items:
    raise SystemExit("Error: NormaHub returned an empty or invalid model catalog.")

def skip_model(model_id, item):
    slug = model_id.strip().lower()
    if slug.startswith("claude") or "claude" in slug.split("-"):
        return True
    if "image" in slug:
        return True
    endpoints = item.get("endpoints") if isinstance(item.get("endpoints"), list) else []
    if any(isinstance(ep, str) and "images" in ep.lower() for ep in endpoints):
        return True
    pricing = item.get("pricing") if isinstance(item.get("pricing"), dict) else {}
    image_price = pricing.get("image_price")
    try:
        if image_price is not None and float(image_price) > 0:
            return True
    except (TypeError, ValueError):
        pass
    return False

catalog = []
priority = 0
for item in items:
    model_id = item.get("id") if isinstance(item, dict) else None
    if not isinstance(model_id, str) or not model_id.strip():
        continue
    if skip_model(model_id, item):
        continue
    priority += 1
    context = item.get("context_window")
    context = context if isinstance(context, int) and context > 0 else None
    capabilities = item.get("capabilities")
    capabilities = capabilities if isinstance(capabilities, dict) else {}
    catalog.append({
        "slug": model_id,
        "display_name": model_id,
        "description": "Available through NormaHub",
        "default_reasoning_level": "medium",
        "supported_reasoning_levels": [
            {"effort": "low", "description": "Faster responses"},
            {"effort": "medium", "description": "Balanced reasoning"},
            {"effort": "high", "description": "Deeper reasoning"},
        ],
        "shell_type": "unified_exec",
        "visibility": "list",
        "supported_in_api": True,
        "priority": priority,
        "availability_nux": None,
        "upgrade": None,
        "base_instructions": "You are Codex, a coding agent. Work with the user in the current workspace to complete software engineering tasks.",
        "support_verbosity": bool(capabilities.get("verbosity", True)),
        "default_verbosity": None,
        "apply_patch_tool_type": "freeform",
        "truncation_policy": {"mode": "tokens", "limit": 10000},
        "supports_parallel_tool_calls": True,
        "context_window": context,
        "max_context_window": context,
        "experimental_supported_tools": [],
        "input_modalities": ["text", "image"],
    })

if not catalog:
    raise SystemExit("Error: NormaHub catalog contains no valid model IDs.")

catalog_file.write_text(json.dumps({"models": catalog}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

text = config_file.read_text(encoding="utf-8") if config_file.exists() else ""
text = re.sub(r"(?ms)^# BEGIN NORMAHUB CODEX ROOT\n.*?^# END NORMAHUB CODEX ROOT\n?", "", text)
text = re.sub(r"(?ms)^# BEGIN NORMAHUB CODEX PROVIDER\n.*?^# END NORMAHUB CODEX PROVIDER\n?", "", text)
text = re.sub(r"(?ms)^\[model_providers\.normahub\]\s*\n.*?(?=^\[|\Z)", "", text)
table = re.search(r"(?m)^\s*\[", text)
split = table.start() if table else len(text)
root_text, table_text = text[:split], text[split:]
root_text = re.sub(r"(?m)^(model|model_provider|model_catalog_json)\s*=.*\n?", "", root_text)
text = root_text + table_text

def toml(value):
    return json.dumps(str(value), ensure_ascii=False)

root = (
    "# BEGIN NORMAHUB CODEX ROOT\n"
    f"model = {toml(catalog[0]['slug'])}\n"
    'model_provider = "normahub"\n'
    f"model_catalog_json = {toml(catalog_file)}\n"
    "# END NORMAHUB CODEX ROOT\n\n"
)
provider = (
    "\n# BEGIN NORMAHUB CODEX PROVIDER\n"
    "[model_providers.normahub]\n"
    'name = "NormaHub"\n'
    f"base_url = {toml(os.environ['BASE_URL'])}\n"
    'wire_api = "responses"\n'
    f"experimental_bearer_token = {toml(os.environ['NORMAHUB_KEY'])}\n"
    "# END NORMAHUB CODEX PROVIDER\n"
)
result = root + text.strip() + provider
try:
    import tomllib
    tomllib.loads(result)
except ImportError:
    pass
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"Error: refusing to write invalid config.toml: {exc}")
config_file.write_text(result, encoding="utf-8")
os.chmod(config_file, 0o600)
os.chmod(catalog_file, 0o600)
print(f"Configured {len(catalog)} NormaHub model(s) in {config_file}")
print(f"Default model: {catalog[0]['slug']}")
PY

printf '%s\n' "Restart Codex to apply the new configuration."
