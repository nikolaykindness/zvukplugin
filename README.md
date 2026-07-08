# Плагин «СберЗвук» для Lyrion Music Server / Daphile

Стриминг музыки из [zvuk.com](https://zvuk.com) напрямую через LMS.

## Возможности

- Вход по email/паролю или ручной токен
- Поиск (треки, исполнители, альбомы)
- Плейлисты и избранное
- Воспроизведение FLAC / MP3 320 / MP3 128

## Установка через репозиторий (Additional Repositories)

Рекомендуемый способ для Daphile и LMS.

### Шаг 1 — для пользователя плагина

1. Откройте веб-интерфейс LMS: `http://<ip-вашего-daphile>:9000`
2. **Settings → Manage Plugins**
3. Внизу страницы — **Additional Repositories**
4. Вставьте URL репозитория (если `raw.githubusercontent.com` недоступен из России, используйте jsDelivr):

   ```
   https://cdn.jsdelivr.net/gh/nikolaykindness/zvukplugin@main/repository.xml
   ```

   Альтернатива:

   ```
   https://raw.githubusercontent.com/nikolaykindness/zvukplugin/main/repository.xml
   ```

5. Нажмите **Apply**
6. Перезапустите LMS / Daphile
7. Снова откройте **Manage Plugins** — появится секция репозитория
8. Найдите **СберЗвук** → **Install** → **Apply** → перезапуск
9. После перезапуска плагин должен сразу появиться в **Active Plugins**
10. Нажмите **Settings** у плагина (или **Settings → Plugins → СберЗвук**) → войдите в аккаунт

> **Важно (v0.1.3+):** zip скачивается через jsDelivr, а не с GitHub Releases — это надёжнее из России. Используйте версию **0.1.3** или новее.

### Если плагин «пропадает» после установки

В версиях до 0.1.3 архив собирался на Windows с обратными слэшами (`Zvuk\install.xml`). LMS на Linux (Daphile) не мог его распаковать, и плагин исчезал после перезапуска. Обновитесь до **v0.1.3** или установите вручную (см. ниже).

### Шаг 2 — для автора: как опубликовать репозиторий

#### 2.1. Настройка

Отредактируйте `repo.config.json`:

```json
{
  "github_user": "ваш-логин-github",
  "github_repo": "zvukplugin",
  "version": "0.1.0",
  "creator": "Ваше имя",
  "email": "ваш@email.com"
}
```

#### 2.2. Сборка релиза

В PowerShell из корня проекта:

```powershell
.\scripts\build-release.ps1
```

Скрипт создаёт:

| Файл | Назначение |
|------|------------|
| `dist/Zvuk-0.1.0.zip` | Архив плагина для LMS |
| `repository.xml` | Каталог для Additional Repositories |
| `dist/repository.xml` | Копия каталога |

#### 2.3. Загрузка на GitHub

1. Создайте репозиторий на GitHub (например `zvukplugin`)
2. Загрузите код проекта (`git push`)
3. Убедитесь, что **`repository.xml` в корне репозитория** закоммичен (его генерирует build-скрипт)
4. Создайте **Release** с тегом `v0.1.0` (тег должен совпадать с версией в `repo.config.json`)
5. Прикрепите к релизу файл **`dist/Zvuk-0.1.0.zip`**

> Важно: LMS проверяет SHA1 из `repository.xml`. После каждого изменения zip **пересоберите** скриптом и обновите `repository.xml` в git.

#### 2.4. URL для пользователей

После публикации дайте пользователям этот URL (подставьте свой логин):

```
https://raw.githubusercontent.com/ВАШ_ЛОГИН/zvukplugin/main/repository.xml
```

Проверка: откройте URL в браузере — должен открыться XML с полями `<url>` и `<sha>`.

### Обновление плагина

1. Увеличьте `version` в `repo.config.json` и `Plugins/Zvuk/install.xml`
2. Запустите `.\scripts\build-release.ps1`
3. Закоммитьте обновлённый `repository.xml`
4. Создайте новый GitHub Release (`v0.1.2` и т.д.) с новым zip
5. Пользователи: **Manage Plugins → Apply** — LMS предложит обновление

## Ручная установка (без репозитория)

Надёжный способ, если репозиторий не скачивает zip.

1. Скачайте `releases/Zvuk-0.1.3.zip` из репозитория или возьмите папку `Plugins/Zvuk` из исходников
2. Распакуйте в каталог плагинов LMS так, чтобы получилось:

   ```
   .../Plugins/Zvuk/install.xml
   .../Plugins/Zvuk/Plugin.pm
   ```

   На Daphile обычно:

   ```
   /daphile/lsvc/Plugins/Zvuk/
   ```

3. Перезапустите LMS
4. Включите плагин в **Manage Plugins** → **Apply** → перезапуск
5. Откройте **Settings** у плагина СберЗвук

## Отладка

```bash
--d_plugins=plugin.zvuk
```

## Структура проекта

```
zvukplugin/
├── Plugins/Zvuk/       # Исходники плагина
├── repository.xml      # Каталог для LMS (генерируется сборкой)
├── repo.config.json    # Настройки публикации
├── scripts/
│   └── build-release.ps1
└── dist/               # Готовые артефакты (zip + repository.xml)
```
