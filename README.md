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
4. Вставьте URL репозитория (пример, замените на свой после публикации):

   ```
   https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/zvukplugin/main/repository.xml
   ```

5. Нажмите **Apply**
6. Перезапустите LMS / Daphile
7. Снова откройте **Manage Plugins** — появится секция репозитория
8. Найдите **СберЗвук** → **Install** → **Apply** → перезапуск
9. **Settings → Plugins → СберЗвук** — войдите в аккаунт

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
4. Создайте новый GitHub Release (`v0.1.1` и т.д.) с новым zip
5. Пользователи: **Manage Plugins → Apply** — LMS предложит обновление

## Ручная установка (без репозитория)

1. Скопируйте папку `Plugins/Zvuk` в каталог плагинов LMS:

   ```
   /slimserver/Plugins/Zvuk/
   ```

   На Daphile обычно:

   ```
   /daphile/lsvc/Plugins/Zvuk/
   ```

2. Перезапустите LMS
3. Включите плагин в **Manage Plugins**

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
