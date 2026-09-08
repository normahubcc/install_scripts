# NormaHub Installation Scripts

Скрипты для автоматической настройки AI-ассистентов кодирования для работы с [NormaHub API](https://normahub.cc).

## Описание

NormaHub — это сервис-шлюз, предоставляющий доступ к различным языковым моделям через единый API. Эти скрипты автоматически настраивают популярные AI-инструменты для разработчиков на использование NormaHub в качестве провайдера моделей.

## Поддерживаемые инструменты

### Claude Code
Официальный AI-ассистент от Anthropic для разработки ПО.

- **Скрипты:** `install_claude.sh` (Linux/macOS), `install_claude.bat` (Windows)
- **Настраиваемые модели:** Только модели Claude (claude-opus, claude-sonnet, claude-fable и т.д.)
- **Файл конфигурации:** `~/.claude/settings.json`

### Codex
AI-агент для программирования в командной строке.

- **Скрипты:** `install_codex.sh` (Linux/macOS), `install_codex.bat` (Windows)
- **Настраиваемые модели:** Не-Claude модели (GPT, DeepSeek, Qwen и т.д.)
- **Файл конфигурации:** `~/.codex/config.toml`

### OpenCode
Универсальный AI-инструмент для программирования с поддержкой нескольких провайдеров.

- **Скрипты:** `install_opencode.sh` (Linux/macOS), `install_opencode.bat` (Windows)
- **Настраиваемые модели:** Все доступные модели (OpenAI и Anthropic)
- **Файл конфигурации:** `~/.config/opencode/opencode.json`

## Требования

### Linux/macOS
- `curl` — для загрузки каталога моделей
- `python3` — для обработки конфигурации
- Установленный целевой AI-инструмент (Claude Code / Codex / OpenCode)

### Windows
- PowerShell 5.0 или выше
- Установленный целевой AI-инструмент (Claude Code / Codex / OpenCode)

## Установка

### Получение API-ключа

1. Зарегистрируйтесь на [NormaHub](https://normahub.cc)
2. Получите API-ключ в личном кабинете
3. Скопируйте ключ для использования в скрипте

### Linux/macOS

```bash
# Для Claude Code
chmod +x install_claude.sh
./install_claude.sh

# Для Codex
chmod +x install_codex.sh
./install_codex.sh

# Для OpenCode
chmod +x install_opencode.sh
./install_opencode.sh
```

### Windows

```cmd
# Для Claude Code
install_claude.bat

# Для Codex
install_codex.bat

# Для OpenCode
install_opencode.bat
```

При запуске скрипт запросит ваш NormaHub API-ключ (ввод будет скрыт для безопасности).

## Как это работает

Каждый скрипт выполняет следующие действия:

1. **Запрашивает API-ключ** — безопасный ввод без отображения на экране
2. **Загружает каталог моделей** — получает список доступных моделей с NormaHub API
3. **Фильтрует модели** — выбирает только модели, совместимые с целевым инструментом
4. **Обновляет конфигурацию** — записывает настройки в конфигурационный файл инструмента:
   - Устанавливает базовый URL на NormaHub API
   - Сохраняет API-ключ
   - Настраивает модель по умолчанию
   - Создает каталог доступных моделей
5. **Устанавливает права доступа** — защищает файлы с чувствительными данными (chmod 600)

## Безопасность

- API-ключи хранятся локально в конфигурационных файлах с ограниченными правами доступа
- Ввод ключа скрыт от отображения в терминале
- Скрипты проверяют существующие конфигурации перед перезаписью
- Windows-версии используют PowerShell SecureString для обработки ключей

## Что настраивается

### Claude Code
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

### Codex
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

### OpenCode
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

## Использование после установки

После успешной настройки:

1. Перезапустите соответствующий AI-инструмент
2. Инструмент автоматически будет использовать NormaHub API
3. Вы сможете выбирать из всех доступных моделей в каталоге NormaHub

## Устранение неполадок

**Ошибка: "curl is required" / "python3 is required"**
- Установите недостающую утилиту через пакетный менеджер вашей системы

**Ошибка: "failed to download" модели**
- Проверьте подключение к интернету
- Убедитесь, что https://api.normahub.cc доступен

**Ошибка: "API key cannot be empty"**
- Убедитесь, что вы ввели ключ (даже если он не отображается)

**Конфигурация не применяется**
- Убедитесь, что полностью перезапустили инструмент
- Проверьте права доступа к конфигурационным файлам
- Посмотрите логи инструмента для подробностей

## Лицензия

Эти скрипты предоставляются "как есть" для автоматизации настройки AI-инструментов с NormaHub.

## Поддержка

- **NormaHub:** [https://normahub.cc](https://normahub.cc)
- **Issues:** [GitHub Issues](../../issues)

---

**Примечание:** Эти скрипты предназначены для настройки клиентских инструментов. Вам нужен действующий аккаунт NormaHub и API-ключ для использования сервиса.
