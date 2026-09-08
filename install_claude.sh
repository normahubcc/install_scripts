#!/usr/bin/env sh
set -eu

API_URL="https://api.normahub.cc/api/v1/public/models"
BASE_URL="https://api.normahub.cc"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CACHE_DIR="$CLAUDE_DIR/cache"
CATALOG_FILE="$CACHE_DIR/gateway-models.json"

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

mkdir -p "$CLAUDE_DIR"
chmod 700 "$CLAUDE_DIR" 2>/dev/null || true
mkdir -p "$CACHE_DIR"
TMP_MODELS=$(mktemp "${TMPDIR:-/tmp}/normahub-models.XXXXXX")
trap 'rm -f "$TMP_MODELS"' EXIT HUP INT TERM

if ! curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$API_URL" -o "$TMP_MODELS"; then
  printf '%s\n' "Error: failed to download $API_URL" >&2
  exit 1
fi

NORMAHUB_KEY="$NORMAHUB_KEY" SETTINGS_FILE="$SETTINGS_FILE" CATALOG_FILE="$CATALOG_FILE" \
  TMP_MODELS="$TMP_MODELS" BASE_URL="$BASE_URL" python3 <<'PY'
import json
import os
from pathlib import Path

settings_file = Path(os.environ["SETTINGS_FILE"])
catalog_file = Path(os.environ["CATALOG_FILE"])
with open(os.environ["TMP_MODELS"], encoding="utf-8") as source:
    payload = json.load(source)

items = payload.get("models")
if not isinstance(items, list) or not items:
    raise SystemExit("Error: NormaHub returned an empty or invalid model catalog.")

models = []
model_items = {}
for item in items:
    if not isinstance(item, dict):
        continue
    model_id = item.get("id")
    if not isinstance(model_id, str) or not model_id.strip():
        continue
    slug = model_id.strip().lower()
    if not (slug.startswith("claude") or "claude" in slug.split("-")):
        continue
    if "image" in slug:
        continue
    endpoints = item.get("endpoints") if isinstance(item.get("endpoints"), list) else []
    if any(isinstance(ep, str) and "images" in ep.lower() for ep in endpoints):
        continue
    model_id = model_id.strip()
    models.append(model_id)
    model_items[model_id] = item

if not models:
    raise SystemExit("Error: NormaHub catalog contains no valid Claude model IDs.")

try:
    settings = json.loads(settings_file.read_text(encoding="utf-8")) if settings_file.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"Error: refusing to overwrite invalid settings.json: {exc}")
if not isinstance(settings, dict):
    raise SystemExit("Error: settings.json must contain a JSON object.")

env = settings.get("env")
if not isinstance(env, dict):
    env = {}
settings["env"] = env
env["ANTHROPIC_BASE_URL"] = os.environ["BASE_URL"]
env["ANTHROPIC_AUTH_TOKEN"] = os.environ["NORMAHUB_KEY"]
env["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
# NormaHub exposes the real model IDs as-is and does not accept Claude Code's
# synthetic "[1m]" model suffix used for native 1M-context variants.
env["CLAUDE_CODE_DISABLE_1M_CONTEXT"] = "1"

# The public catalog is ordered by merchandising priority, not compatibility.
# Prefer a released model so an experimental first entry cannot break startup.
preferred = ["claude-opus-4-6", "claude-sonnet-4-6"]
default_model = next((model for model in preferred if model in model_items), models[0])
settings["model"] = default_model

# Claude Code's built-in aliases resolve to future Anthropic IDs unless a
# gateway explicitly pins them. Keep those aliases on IDs exposed by NormaHub.
if "claude-opus-4-6" in model_items:
    env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = "claude-opus-4-6"
if "claude-sonnet-4-6" in model_items:
    env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = "claude-sonnet-4-6"
if "claude-fable-5-1" in model_items:
    env["ANTHROPIC_DEFAULT_FABLE_MODEL"] = "claude-fable-5-1"

settings_file.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
catalog_file.write_text(json.dumps({"data": [{"id": model} for model in models]}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.chmod(settings_file, 0o600)
os.chmod(catalog_file, 0o600)
print(f"Configured {len(models)} NormaHub Claude model(s) in {settings_file}")
print(f"Default model: {default_model}")
PY

printf '%s\n' "Restart Claude Code to apply the new configuration."
