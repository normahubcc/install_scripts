<p align="center">
  <a href="https://normahub.cc">
    <img src="https://raw.githubusercontent.com/normahubcc/.github/main/docs/images/logo.png" alt="NormaHub" width="120" />
  </a>
</p>

# NormaHub Setup Scripts

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux_|_macOS_|_Windows-blue.svg?style=flat-square)](#требования)
[![NormaHub API](https://img.shields.io/badge/API-normahub.cc-6366f1.svg?style=flat-square)](https://normahub.cc)

Скрипты быстрой настройки подключения AI-инструментов (Claude Code, Codex, OpenCode) к [NormaHub API](https://normahub.cc).

## Быстрый старт

Нужен API-ключ NormaHub. Получить его можно в [личном кабинете](https://normahub.cc).

### Linux/macOS

```bash
# Claude Code: только модели Claude
chmod +x install_claude.sh && ./install_claude.sh

# Codex: GPT, DeepSeek, Qwen и другие модели, кроме Claude
chmod +x install_codex.sh && ./install_codex.sh

# OpenCode: все доступные модели
chmod +x install_opencode.sh && ./install_opencode.sh
```

### Windows

```cmd
REM Claude Code: только модели Claude
install_claude.bat

REM Codex: GPT, DeepSeek, Qwen и другие модели, кроме Claude
install_codex.bat

REM OpenCode: все доступные модели
install_opencode.bat
```

Каждый скрипт запросит API-ключ скрытым вводом. После завершения перезапустите соответствующий AI-инструмент.

## Что выбрать

| Инструмент | Модели | Платформы |
| --- | --- | --- |
| Claude Code | Только Claude | Linux, macOS, Windows |
| Codex | Все модели, кроме Claude | Linux, macOS, Windows |
| OpenCode | Все доступные модели | Linux, macOS, Windows |

## Требования

### Linux/macOS

- `curl`
- `python3`
- Установленный целевой AI-инструмент

### Windows

- PowerShell 5.0 или выше
- Установленный целевой AI-инструмент

## Подробности

### Как работает установка

Каждый скрипт:

1. Запрашивает API-ключ без отображения в терминале.
2. Загружает каталог моделей с NormaHub API.
3. Отбирает модели, совместимые с выбранным инструментом.
4. Записывает URL API, ключ, модель по умолчанию и каталог моделей в конфигурацию.
5. Ограничивает права доступа к конфигурационным файлам на Linux/macOS.

### Файлы конфигурации

- Claude Code: `~/.claude/settings.json`
- Codex: `~/.codex/config.toml`
- OpenCode: `~/.config/opencode/opencode.json`

Пути можно изменить переменными окружения:

- Claude Code: `CLAUDE_CONFIG_DIR`
- Codex: `CODEX_HOME`
- OpenCode: `OPENCODE_CONFIG_DIR`

### Что настраивается

#### Claude Code

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.normahub.cc",
    "ANTHROPIC_AUTH_TOKEN": "ваш-ключ",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "CLAUDE_CODE_DISABLE_1M_CONTEXT": "1"
  },
  "model": "claude-opus-4-6"
}
```

#### Codex

```toml
model = "модель-по-умолчанию"
model_provider = "normahub"
model_catalog_json = "/путь/к/каталогу.json"

[model_providers.normahub]
name = "NormaHub"
base_url = "https://api.normahub.cc/v1"
wire_api = "responses"
experimental_bearer_token = "ваш-ключ"
```

#### OpenCode

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "normahub/модель-по-умолчанию",
  "provider": {
    "normahub": {
      "npm": "@ai-sdk/openai-compatible",
      "apiKey": "ваш-ключ",
      "baseURL": "https://api.normahub.cc/v1"
    },
    "normahub-anthropic": {
      "npm": "@ai-sdk/anthropic",
      "apiKey": "ваш-ключ",
      "baseURL": "https://api.normahub.cc/v1"
    }
  }
}
```

### Безопасность

- API-ключ хранится локально в конфигурационном файле.
- Ввод ключа скрыт в терминале.
- Скрипты учитывают существующую конфигурацию перед обновлением.
- Windows-версии используют PowerShell `SecureString`.

### Устранение неполадок

**`curl is required` или `python3 is required`**

Установите недостающую утилиту через пакетный менеджер системы.

**`failed to download` моделей**

Проверьте подключение к интернету и доступность `https://api.normahub.cc`.

**`API key cannot be empty`**

Повторите запуск и введите API-ключ. При вводе символы не отображаются.

**Конфигурация не применяется**

Полностью перезапустите инструмент и проверьте права доступа к конфигурационному файлу.

## Поддержка

- NormaHub: [normahub.cc](https://normahub.cc)
- Issues: [GitHub Issues](../../issues)

## Лицензия

Скрипты предоставляются «как есть» для автоматизации настройки AI-инструментов с NormaHub.
