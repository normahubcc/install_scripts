#!/usr/bin/env sh
set -eu

API_URL="https://api.normahub.cc/api/v1/public/models"
BASE_URL="https://api.normahub.cc/v1"
OPENCODE_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
CONFIG_FILE="$OPENCODE_DIR/opencode.json"

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

mkdir -p "$OPENCODE_DIR"
chmod 700 "$OPENCODE_DIR" 2>/dev/null || true
TMP_MODELS=$(mktemp "${TMPDIR:-/tmp}/normahub-models.XXXXXX")
trap 'rm -f "$TMP_MODELS"' EXIT HUP INT TERM

if ! curl --fail --silent --show-error --location --retry 3 --retry-all-errors "$API_URL" -o "$TMP_MODELS"; then
  printf '%s\n' "Error: failed to download $API_URL" >&2
  exit 1
fi

NORMAHUB_KEY="$NORMAHUB_KEY" CONFIG_FILE="$CONFIG_FILE" \
  TMP_MODELS="$TMP_MODELS" BASE_URL="$BASE_URL" python3 <<'PY'
import json
import os
from pathlib import Path

config_file = Path(os.environ["CONFIG_FILE"])

with open(os.environ["TMP_MODELS"], encoding="utf-8") as source:
    payload = json.load(source)

items = payload.get("models")
if not isinstance(items, list):
    items = payload.get("data")
if not isinstance(items, list) or not items:
    raise SystemExit("Error: NormaHub returned an empty or invalid model catalog.")

def skip_model(model_id, item):
    slug = model_id.strip().lower()
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

openai_models = {}
anthropic_models = {}
for item in items:
    model_id = item.get("id") if isinstance(item, dict) else None
    if not isinstance(model_id, str) or not model_id.strip():
        continue
    if skip_model(model_id, item):
        continue
    context = item.get("context_window")
    context = context if isinstance(context, int) and context > 0 else None
    limits = item.get("limits") if isinstance(item.get("limits"), dict) else {}
    output = item.get("max_output_tokens")
    if not isinstance(output, int) or output <= 0:
        output = item.get("output_tokens")
    if not isinstance(output, int) or output <= 0:
        output = limits.get("output")
    if not isinstance(output, int) or output <= 0:
        output = 65536
    capabilities = item.get("capabilities")
    capabilities = capabilities if isinstance(capabilities, dict) else {}
    model = {
        "name": model_id,
        "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
        }
    }
    model["limit"] = {"context": context or 128000, "output": output}
    slug = model_id.strip().lower()
    if slug.startswith("claude") or "claude" in slug.split("-"):
        anthropic_models[model_id] = model
    else:
        openai_models[model_id] = model

if not openai_models and not anthropic_models:
    raise SystemExit("Error: NormaHub catalog contains no valid model IDs.")

try:
    raw_config = config_file.read_text(encoding="utf-8") if config_file.exists() else ""
    config = json.loads(raw_config) if raw_config.strip() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"Error: refusing to overwrite invalid opencode.json: {exc}")
if not isinstance(config, dict):
    raise SystemExit("Error: opencode.json must contain a JSON object.")

if "provider" not in config or not isinstance(config["provider"], dict):
    config["provider"] = {}

providers = config["provider"]
if openai_models:
    providers["normahub"] = {
        "npm": "@ai-sdk/openai-compatible",
        "name": "NormaHub (OpenAI)",
        "options": {
            "apiKey": os.environ["NORMAHUB_KEY"],
            "baseURL": os.environ["BASE_URL"]
        },
        "models": openai_models
    }
if anthropic_models:
    providers["normahub-anthropic"] = {
        "npm": "@ai-sdk/anthropic",
        "name": "NormaHub (Claude)",
        "options": {
            "apiKey": os.environ["NORMAHUB_KEY"],
            "baseURL": os.environ["BASE_URL"],
            "headers": {
                "Authorization": f"Bearer {os.environ['NORMAHUB_KEY']}"
            }
        },
        "models": anthropic_models
    }

if "$schema" not in config:
    config["$schema"] = "https://opencode.ai/config.json"
if not isinstance(config.get("model"), str) or not config["model"]:
    if openai_models:
        config["model"] = f"normahub/{next(iter(openai_models))}"
    else:
        config["model"] = f"normahub-anthropic/{next(iter(anthropic_models))}"

config_file.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.chmod(config_file, 0o600)
print(f"Configured {len(openai_models) + len(anthropic_models)} NormaHub model(s) in {config_file}")
print(f"Default model: {config['model']}")
PY

printf '%s\n' "Restart OpenCode to apply the new configuration."
