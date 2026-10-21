# Установка Filemaster на один сервер

В этом каталоге находится конфигурация для развертывания Filemaster на одном
сервере. Установка, обновление и запуск выполняются через `task`. Команды
`docker compose` используйте только для диагностики: просмотра состояния
контейнеров и логов.

## Требования к серверу

На сервере должны быть доступны:

- Docker Engine с плагином Docker Compose (`docker compose version`);
- Taskfile CLI (`task --version`);
- доступ к Docker registry из `docker_image_registry` в `client-config.yml`
  для загрузки образов, а также доступ к registry поставки для утилиты `fm`,
  если зеркало не содержит её артефакт;
- свободные TCP-порты `80` и `443`;
- DNS-запись для имени Filemaster из `client-config.yml`, указывающая на этот
  сервер;
- TLS-сертификат и закрытый ключ для этого имени;
- доступ к AD FS требуется только при включении входа через AD FS;
- сетевой доступ к LDAP/LDAPS требуется только при включении входа через LDAP.

## Настройка

Создайте файл настроек из шаблона:

```sh
cd config/deploy-compose/edms-adfs
cp client-config.example.yml client-config.yml
```

Заполните `client-config.yml`:

- `config_schema` — версия формата клиентской конфигурации; для этой поставки
  оставьте значение `2`;
- `domain` — полное публичное имя Filemaster без протокола и пути, например
  `filemaster.example.domain`;
- `docker_image_registry` — обязательный префикс registry для Docker-образов
  без завершающего слэша; имена репозиториев и теги не меняются. Оставьте
  значение из шаблона или укажите зеркало с тем же расположением репозиториев;
- `adfs.enabled` — `false`, пока вход через AD FS не нужен, или `true` после
  настройки AD FS;
- `adfs.display_name` — название подключения, отображаемое пользователю;
- `adfs.entity_id` — идентификатор AD FS;
- `adfs.sso_url` — адрес AD FS для входа;
- `adfs.slo_url` — адрес AD FS для выхода;
- `adfs.metadata_url` — адрес XML-метаданных AD FS;
- `ldap.enabled` — `false`, пока LDAP не нужен, или `true` после настройки
  каталога;
- `ldap.name` — название LDAP-федерации в Keycloak;
- `ldap.connection_url` — адрес с протоколом `ldap://` или `ldaps://`;
- `ldap.users_dn` — ветка каталога с пользователями;
- `ldap.bind_dn` и `ldap.bind_password` — учетные данные подключения только для
  чтения каталога;
- `ldap.group_mapping_dn` — ветка каталога с группами;
- `emergency_export.host_path` — каталог на сервере для аварийного экспорта.

Секции `adfs` и `ldap` обязательны, даже когда обе интеграции выключены.
Допустимы только три режима: только LDAP, только AD FS или ни одной внешней
интеграции. При попытке включить LDAP и AD FS одновременно `fm` завершится с
ошибкой до изменения `.env`.

При выключенной интеграции можно оставить безопасные адреса `*.invalid` из
шаблона. Перед включением замените их реальными адресами. Имя подключения
`adfs` входит в поставляемую конфигурацию и не настраивается в
`client-config.yml`. Подробная инструкция по AD FS приведена в [ADFS.md](ADFS.md).

`client-config.yml` не попадает в Git, но содержит пароль `ldap.bind_password`.
Не выводите содержимое этого файла в логи и ограничьте доступ к нему.

Файл `.env` создается автоматически и не предназначен для редактирования.
Файл `.env.release` содержит поставляемые значения и не редактируется.

На хосте с защищенным томом LUKS активируйте поставляемый пример привязок:

```sh
cp docker-compose.override.example.yml docker-compose.override.yml
git check-ignore docker-compose.override.yml
```

Вторая команда должна вывести `docker-compose.override.yml`. Этот локальный,
игнорируемый Git файл направляет данные PostgreSQL, Elasticsearch и MinIO в
`/srv/filemaster`. Остальные именованные тома остаются в каталоге данных Docker.
Создание и проверка защищенного тома описаны в LUKS-инструкциях пакета
`ansible-vault`; не запускайте Compose до монтирования тома и проверки маркера.

На сервере создайте каталоги с UID владельца: PostgreSQL — `1001`,
Elasticsearch — `1000`, MinIO — `0`. Замените `/путь/к/данным` на путь из
override (`/srv/filemaster` в примере). Выполните от имени пользователя с `sudo`:

```sh
DATA_DIR=/путь/к/данным
sudo install -d -m 0750 -o 1001 -g 0 "$DATA_DIR/postgresql"
sudo install -d -m 0750 -o 1000 -g 0 "$DATA_DIR/elasticsearch"
sudo install -d -m 0750 -o 0 -g 0 "$DATA_DIR/minio"
```

## TLS-сертификаты

Разместите сертификат и закрытый ключ в каталоге `caddy/cert`:

```sh
cp /path/to/cert.pem caddy/cert/cert.pem
cp /path/to/key.pem caddy/cert/key.pem
```

Сертификат должен соответствовать значению `domain` из `client-config.yml`.

## Первый запуск

Выполните команды:

```sh
task fm-install
cp client-config.example.yml client-config.yml
nano client-config.yml
task check-config
task bootstrap
```

Описание команд:

- `task fm-install` — устанавливает утилиту `fm` требуемой версии;
- `task check-config` — проверяет настройки и итоговую конфигурацию Docker
  Compose;
- `task bootstrap` — запускает установку поэтапно: инфраструктурные сервисы,
  инициализацию данных, Keycloak, миграции и прикладные сервисы.

Для первой установки без внешней авторизации оставьте `adfs.enabled: false` и
`ldap.enabled: false`, а также адреса `*.invalid` из шаблона. Настройте только
`domain`, путь аварийного экспорта и TLS-сертификаты. В таком состоянии
Filemaster использует локальных пользователей Keycloak.

### Первый локальный администратор

После завершения `task bootstrap` создайте первого пользователя вручную:

1. Откройте `https://FILEMASTER_DOMAIN/keycloak/admin/`, где
   `FILEMASTER_DOMAIN` — значение `domain` из `client-config.yml`.
2. Войдите с учетными данными администратора Keycloak из переменных
   `KEYCLOAK_ADMIN_USERNAME` и `KEYCLOAK_ADMIN_PASSWORD` в сгенерированном
   файле `.env`. Не передавайте эти значения пользователям Filemaster.
3. В левом верхнем углу выберите realm `edms`.
4. В разделе **Users** создайте пользователя и включите его.
5. На вкладке **Credentials** задайте ему постоянный пароль.
6. На вкладке **Groups** добавьте пользователя в группу `/fm-admin`.
7. Откройте `https://FILEMASTER_DOMAIN/` и проверьте вход с созданными
   локальными учетными данными.

Пользователь `edms_sso_api` из realm `master` — служебная учетная запись. Это
не первый пользователь Filemaster, и входить под ней в приложение не следует.

## Проверки перед запуском

Перед выполнением `task bootstrap` убедитесь, что:

- имя из `domain` разрешается в IP-адрес сервера;
- порты `80` и `443` не заняты другими процессами;
- TLS-сертификат и ключ размещены в `caddy/cert`;
- при `adfs.enabled: true` все адреса и идентификаторы AD FS заполнены реальными
  значениями, а не адресами `*.invalid`;
- при `ldap.enabled: true` адрес LDAP, ветки пользователей и групп, bind DN и
  пароль заполнены реальными значениями, LDAP доступен с сервера, а сертификат
  LDAPS доверен контейнеру Keycloak;
- одновременно включена не более чем одна из интеграций LDAP и AD FS;
- каталог `emergency_export.host_path` существует и доступен Docker-демону.

## Проверки после запуска

Проверьте состояние контейнеров:

```sh
docker compose ps
```

Контейнеры должны находиться в состоянии `running` или `healthy`.

Проверьте доступ к Filemaster:

```sh
curl -I https://filemaster.example.domain/
```

Замените `filemaster.example.domain` на значение `domain` из
`client-config.yml`.

## Обновление настроек

После изменения `client-config.yml` выполните:

```sh
task config-render
task check-config
```

Если команда сообщает о несовпадении версии `fm`, выполните:

```sh
task fm-install
task check-config
```

После успешной проверки примените изменения полным запуском:

```sh
task bootstrap
```

## Включение LDAP после установки

Шаблон использует стандартные атрибуты Active Directory: `sAMAccountName` для
логина, `givenName` для имени, `sn` для фамилии и `mail` для email. Мапперы
работают только на чтение; `MSAD account controls` передаёт состояние учётной
записи AD в Keycloak. Для отображения пользователя в списках SSO и FileMaster
должны быть заполнены имя, фамилия и email.

Шаблон не содержит мапперов `full name` и не извлекает ФИО из `cn`. Однако
Keycloak может автоматически создать такой маппер при добавлении LDAP-провайдера.
После bootstrap проверьте фактический набор мапперов: отсутствие `full name`
в JSON-шаблоне не гарантирует его отсутствие в Keycloak.

1. Проверьте сетевой доступ к LDAP/LDAPS. Для LDAPS цепочка сертификатов должна
   быть доверена контейнеру Keycloak.
2. Заполните все поля секции `ldap` реальными значениями.
3. Установите `adfs.enabled: false` и `ldap.enabled: true`.
4. Проверьте и примените конфигурацию:

```sh
task check-config
task keycloak-bootstrap
```

`task check-config` должен завершиться успешно до изменения Keycloak. Команда
`task keycloak-bootstrap` применяет LDAP-федерацию повторяемым способом. После
применения проверьте вход через LDAP и вход локального администратора: локальные
пользователи остаются доступны при включенном LDAP.

Чтобы отключить LDAP, сначала проверьте вход локального администратора, затем
установите `ldap.enabled: false` и повторите две команды выше. Отключение не
удаляет локальных пользователей Keycloak.

## Включение AD FS после установки

1. Настройте Relying Party Trust по инструкции [ADFS.md](ADFS.md).
2. В `client-config.yml` замените все значения `*.invalid` реальными адресами
   и идентификатором AD FS.
3. Установите `adfs.enabled: true`.
4. Примените изменение:

```sh
task check-config
task keycloak-bootstrap
```

`task check-config` должен завершиться успешно до изменения Keycloak. Команда
`task keycloak-bootstrap` обновляет существующее подключение `adfs` через
Keycloak Admin API; перезапуск Keycloak и сервисов Filemaster не требуется.
Повторный запуск этих двух команд безопасен.

После применения проверьте оба варианта входа: локальный логин и кнопку AD FS.
Локальный вход остается доступен и после включения AD FS.

Если email из AD FS совпадает с существующим локальным пользователем, Keycloak
связывает внешнюю учетную запись с этим пользователем. Если совпадения по email
нет, проверяется имя пользователя. Его существующие группы и права сохраняются.
Если совпадения нет, Keycloak создает отдельного пользователя без
автоматического добавления в `/fm-admin`.

## Отключение AD FS

Перед отключением:

- проверьте вход локального пользователя из группы `/fm-admin`;
- задайте локальные пароли всем созданным через AD FS пользователям, которым
  потребуется доступ после отключения.

Затем установите `adfs.enabled: false` и выполните те же команды:

```sh
task check-config
task keycloak-bootstrap
```

Отключение запрещает новые входы через AD FS, но не удаляет подключение,
пользователей или связи учетных записей. Уже открытые сеансы остаются активными
до настроенного срока жизни — в поставляемой конфигурации не более семи дней.
Если сеансы нужно завершить немедленно, сделайте это отдельно через
административные средства Keycloak. Отключение AD FS само по себе не создает
локальные пароли.

## Аварийный экспорт

Путь для экспорта задается в `emergency_export.host_path`. Запуск экспорта:

```sh
task emergency-export -- --latest-only --full-path-prefix=/optional/prefix
```

Параметры:

- `--latest-only` — экспортировать только последнюю версию каждого файла;
- `--full-path-prefix=/path` — экспортировать только файлы из указанного
  раздела Filemaster.

## Полная индексация

После первого запуска или существенных изменений данных выполните полную
индексацию:

```sh
task searchp-full-index
```

## Перенос файлов с локального диска в Filemaster

Для переноса файлов используйте утилиту `file-migrator`:

```sh
./file-migrator/migrate \
  --source /path/to/source \
  --destination / \
  --fm-endpoint "https://filemaster.example.domain"
```

Замените путь к исходным файлам и адрес Filemaster на актуальные значения.

## Мониторинг

Сервисы развертывания предоставляют метрики в формате Prometheus. Для сбора
метрик используйте следующие порты и пути:

| Сервис | Порт на сервере | Путь |
| :--- | ---: | :--- |
| `edms-server` | 10081 | `/metrics` |
| `sso-server` | 10082 | `/metrics` |
| `audit-log` | 10083 | `/metrics` |
| `edms-notifications` | 10084 | `/metrics` |
| `previewer-server` | 12112 | `/metrics` |
| `pdf-text-storage-server` | 12113 | `/metrics` |
| `searchp-server` | 9002 | `/metrics` |

Пример конфигурации Prometheus:

```yaml
scrape_configs:
  - job_name: edms-services
    static_configs:
      - targets:
          - '<server-ip>:10081' # edms-server
          - '<server-ip>:10082' # sso-server
          - '<server-ip>:10083' # audit-log
          - '<server-ip>:10084' # edms-notifications
          - '<server-ip>:12112' # previewer-server
          - '<server-ip>:12113' # pdf-text-storage-server
          - '<server-ip>:9002'  # searchp-server
```

## Переустановка

Для полной остановки и удаления контейнеров и именованных томов выполните:

```sh
task wipe
task bootstrap
```

Команда `task wipe` безвозвратно удаляет данные.

## Справочник команд

- `task -l` — список доступных команд;
- `task check-config` — проверка настроек и Compose;
- `task bootstrap` — штатный запуск всей установки;
- `task keycloak-bootstrap` — повторный импорт настроек Keycloak;
- `task emergency-export` — аварийный экспорт файлов;
- `task searchp-full-index` — полная индексация;
- `task wipe` — остановка и удаление контейнеров и томов.
