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

## Шаг 3. Включение подключения в Filemaster

В `client-config.yml` замените все адреса `*.invalid` значениями настроенного
AD FS, затем установите:

```yaml
adfs:
  enabled: true
```

Проверьте и примените конфигурацию:

```sh
task check-config
task keycloak-bootstrap
```

Перезапуск Keycloak или сервисов Filemaster не требуется.

## Шаг 4. Проверка входа и связывания пользователей

Проверьте следующие сценарии:

1. На странице входа появилась кнопка с текстом из `adfs.display_name`, при
   этом форма локального входа осталась доступна.
2. Пользователь AD FS с email, совпадающим с локальным пользователем, входит в
   ту же учетную запись Filemaster. Если совпадения по email нет, Keycloak
   проверяет имя пользователя. Существующее членство локального пользователя в
   группах, включая `/fm-admin`, сохраняется.
3. Пользователь AD FS без совпадения входит в новую отдельную учетную запись.
   Она не добавляется автоматически в `/fm-admin` или другие группы.

Если AD FS снова выключить через `adfs.enabled: false` и применить те же две
команды, кнопка AD FS должна исчезнуть для новых входов, а локальный вход —
остаться доступным. Активные сеансы при этом не завершаются автоматически.
