# Инструкция по настройке AD FS для интеграции с Filemaster (SAML 2.0)

В этой инструкции `FILEMASTER_DOMAIN` — полное публичное имя Filemaster из
поля `domain` файла `client-config.yml`, например
`filemaster.example.domain`.

Псевдоним подключения `adfs` входит в поставляемую конфигурацию и не
настраивается в `client-config.yml`. Поэтому адрес обратного вызова всегда
оканчивается на `/broker/adfs/endpoint`. Локальный вход в Filemaster остается
доступен независимо от состояния интеграции.

## Шаг 1. Создание отношения доверия (Relying Party Trust)

1. Откройте консоль AD FS Management.
2. Перейдите в дерево консоли, нажмите правой кнопкой мыши на папку Relying Party Trusts и выберите Add Relying Party Trust...
3. В мастере добавления выберите вариант Claims aware и нажмите Start.
4. На этапе выбора источника данных выберите Enter data about the relying party manually.
5. Укажите отображаемое имя (Display Name), например: Filemaster.
6. На этапе настройки сертификата (Configure Certificate) действия можно пропустить.
7. В разделе настройки URL (Configure URL) установите флажок Enable support for the SAML 2.0 WebSSO Protocol.
8. В поле Relying party SAML 2.0 SSO Service URL введите адрес эндпоинта Keycloak:
    https://FILEMASTER_DOMAIN/keycloak/realms/edms/broker/adfs/endpoint
9. На этапе настройки идентификаторов (Configure Identifiers) добавьте Relying party trust identifier:
    https://FILEMASTER_DOMAIN/keycloak/realms/edms
10. В разделе выбора политики управления доступом (Choose Access Control Policy) выберите политику по умолчанию: Permit Everyone.
11. Для полного выхода через AD FS после создания доверия настройте SAML Logout
    и сертификат подписи (шаг 3), затем включите `adfs.sign_requests: true`.
    Без этого logout остаётся на Keycloak (без MSIS7054), а сеанс AD FS может
    остаться живым.

## Шаг 2. Настройка Claim Issuance Policy

После создания доверия необходимо настроить передачу атрибутов пользователя. Нажмите правой кнопкой мыши на созданную запись (Filemaster) и выберите Edit Claim Issuance Policy...

Правило №1: Transform Rule
Данное правило необходимо для передачи идентификатора пользователя.

1. Нажмите Add Rule... и выберите тип шаблона: Transform an Incoming Claim.
2. Укажите имя правила (например, NameID Transformation).
3. Установите следующие параметры:
    * Incoming claim type: Windows account name
    * Outgoing claim type: Name ID
    * Outgoing name ID format: Windows Qualified Domain Name

Правило №2: Передача атрибутов LDAP (LDAP Attributes)
Данное правило сопоставляет поля Active Directory с атрибутами, которые получит Keycloak.

1. Нажмите Add Rule... и выберите тип шаблона: Send LDAP Attributes as Claims.
2. Укажите имя правила (например, LDAP Attributes Mapping).
3. В поле Attribute store выберите Active Directory.
4. Настройте таблицу сопоставления (Mapping of LDAP attributes):


| LDAP Attribute (Active Directory) | Outgoing Claim Type (Keycloak Attribute) |
| - | - |
| SAM-Account-Name | Subject Name |
| E-Mail-Addresses | E-Mail Address |
| Surname | lastName |
| Given-Name | firstName |
| objectSID | SID |


5. Нажмите Finish, затем OK, чтобы сохранить изменения.

## Шаг 3. Endpoint выхода (SAML Logout) и сертификат подписи

Без этих настроек вход через AD FS может работать, а выход — останавливаться
на промежуточной странице Keycloak вместо завершения сеанса в AD FS.

Откройте свойства созданного Relying Party Trust (Properties).

### Endpoints: SAML Logout

1. Перейдите на вкладку Endpoints и нажмите Add SAML...
2. Задайте параметры:

| Параметр | Значение |
| - | - |
| Endpoint type | SAML Logout |
| Binding | Redirect |
| Trusted URL | `https://FILEMASTER_DOMAIN/keycloak/realms/edms/broker/adfs/endpoint` |
| Response URL | `https://FILEMASTER_DOMAIN/keycloak/realms/edms/broker/adfs/endpoint` |

3. Нажмите OK.

Пример для `domain: filemaster.kkmp.tech`:

```text
https://filemaster.kkmp.tech/keycloak/realms/edms/broker/adfs/endpoint
```

Оба поля (Trusted URL и Response URL) указывают на один и тот же эндпоинт
брокера Keycloak. Binding Redirect соответствует настройке поставки
(`postBindingLogout: false`).

### Signature: сертификат Keycloak

AD FS проверяет подпись LogoutRequest от Keycloak. Сертификат realm нужно
добавить на вкладку Signature Relying Party Trust.

#### Как получить сертификат

Вариант A — Admin Console Keycloak:

1. Откройте `https://FILEMASTER_DOMAIN/keycloak/admin/`.
2. Выберите realm `edms`.
3. Перейдите в Realm settings → Keys.
4. В строке активного ключа с алгоритмом RS256 (тип SIG) нажмите Certificate.
5. Скопируйте содержимое окна в файл `keycloak-edms.cer` в формате PEM:

```text
-----BEGIN CERTIFICATE-----
...содержимое из окна Certificate...
-----END CERTIFICATE-----
```

Вариант B — SAML descriptor брокера (без входа в Admin Console):

1. Откройте в браузере или скачайте XML:

```text
https://FILEMASTER_DOMAIN/keycloak/realms/edms/broker/adfs/endpoint/descriptor
```

2. Найдите элемент `X509Certificate` внутри `KeyDescriptor` с
   `use="signing"` (или первый `X509Certificate`, если `use` не указан).
3. Оберните Base64-значение в PEM-заголовки, как в варианте A, и сохраните
   как `keycloak-edms.cer`.

С сервера Filemaster тот же файл можно собрать командой:

```sh
DOMAIN="$(grep -E '^domain:' client-config.yml | awk '{print $2}')"
curl -fsS "https://${DOMAIN}/keycloak/realms/edms/broker/adfs/endpoint/descriptor" \
  | sed -n 's/.*<dsig:X509Certificate>\([^<]*\)<\/dsig:X509Certificate>.*/\1/p; s/.*<ds:X509Certificate>\([^<]*\)<\/ds:X509Certificate>.*/\1/p; s/.*<X509Certificate>\([^<]*\)<\/X509Certificate>.*/\1/p' \
  | head -n1 \
  | fold -w 64 \
  | awk 'BEGIN{print "-----BEGIN CERTIFICATE-----"} {print} END{print "-----END CERTIFICATE-----"}' \
  > keycloak-edms.cer
```

#### Добавление в AD FS

1. В свойствах Relying Party Trust откройте вкладку Signature.
2. Нажмите Add... и выберите файл `keycloak-edms.cer`.
3. При необходимости через View... → Install Certificate установите
   сертификат в хранилище на сервере AD FS.
4. На вкладке Advanced убедитесь, что Secure hash algorithm — SHA-256.
5. Нажмите Apply, затем OK.

После смены ключей подписи realm в Keycloak (ротация Keys) обновите файл
на вкладке Signature, иначе выход через AD FS снова может ломаться.

### Want AuthnRequests Signed и `adfs.sign_requests`

Подписанный SAML login/logout и пропуск страницы логина Keycloak включаются
одним флагом в `client-config.yml`: `adfs.sign_requests`.

| `sign_requests` | Поведение |
| - | - |
| `false` | Страница логина Keycloak с кнопкой AD FS. Logout идёт в Keycloak и возвращает в приложение **без** проброса в AD FS (нет MSIS7054). Сессия AD FS может остаться живой. |
| `true` | Keycloak подписывает AuthnRequest/LogoutRequest (`wantAuthnRequestsSigned`), в IdP попадает `slo_url`, страница логина пропускается (`defaultProvider`). Нужны endpoint SAML Logout и сертификат на Signature (этот шаг). |

Включайте `sign_requests: true` **только после** добавления сертификата Keycloak
на вкладку Signature. Иначе logout упрётся в ошибку AD FS MSIS7054.

Если после включения вход через AD FS перестал работать (сертификат ещё не
добавлен, неверный `.cer` или AD FS отвергает подпись), верните
`sign_requests: false`, выполните `task check-config` и
`task keycloak-bootstrap`. Изменение только в Admin Console не переживает
bootstrap: команда вернёт значения из `client-config.yml`.

## Шаг 4. Включение подключения в Filemaster

В `client-config.yml` замените все адреса `*.invalid` значениями настроенного
AD FS, затем установите:

```yaml
adfs:
  enabled: true
  # После шага 3 (Signature) можно включить подписанный login/logout:
  # sign_requests: true
```

Пока сертификат на Signature не добавлен, оставьте `sign_requests` выключенным
(или не указывайте поле).

Проверьте и примените конфигурацию:

```sh
task check-config
task keycloak-bootstrap
```

Перезапуск Keycloak или сервисов Filemaster не требуется.

После завершения шага 3 включите подписанный режим:

```yaml
adfs:
  enabled: true
  sign_requests: true
```

Снова `task check-config` и `task keycloak-bootstrap`.

## Шаг 5. Проверка входа, выхода и связывания пользователей

При `sign_requests: false` (или поле не задано):

1. На странице входа Keycloak есть кнопка с текстом из `adfs.display_name`,
   форма локального входа доступна.
2. Выход возвращает в приложение без ошибки MSIS7054; сессия AD FS может
   остаться, поэтому повторный вход через кнопку AD FS может пройти без пароля.

При `sign_requests: true` (после шага 3):

1. Страница входа Keycloak пропускается: браузер сразу перенаправляется на форму
   AD FS. Форма локального входа на этом пути не показывается; локальный вход
   снова доступен после отключения AD FS (см. ниже) или при
   `sign_requests: false`.
2. Выход из Filemaster завершает сеанс без промежуточной страницы аккаунта
   Keycloak и без MSIS7054, сессия AD FS завершается. Если появляется ошибка
   AD FS или страница Keycloak — проверьте endpoint SAML Logout (Redirect) и
   сертификат на вкладке Signature (шаг 3).

В обоих режимах:

1. Пользователь AD FS с email, совпадающим с локальным пользователем, входит в
   ту же учетную запись Filemaster. Если совпадения по email нет, Keycloak
   проверяет имя пользователя. Существующее членство локального пользователя в
   группах, включая `/fm-admin`, сохраняется.
2. Пользователь AD FS без совпадения входит в новую отдельную учетную запись.
   Она не добавляется автоматически в `/fm-admin` или другие группы.

Если AD FS снова выключить через `adfs.enabled: false` и применить те же две
команды, кнопка AD FS должна исчезнуть для новых входов, а локальный вход —
остаться доступным. Активные сеансы при этом не завершаются автоматически.
