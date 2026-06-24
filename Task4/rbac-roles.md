# Kubernetes RBAC — Роли и разграничение доступа PropDevelopment

## Контекст

Кластер Kubernetes используется для деплоя бизнес-сервисов PropDevelopment.
В кластере определены следующие namespace-ы по доменам:

| Namespace | Сервисы |
|-----------|---------|
| `sales` | client-mart-app, client-tour-app, client-mart-estate-app, client-crm-app |
| `jku` | tenant-core-app, CRM (собственники), smart-home-service, partner-api-gateway |
| `data` | Greenplum DWH, BI |
| `infra` | auth-service-1, auth-service-2, ingress |
| `monitoring` | Prometheus, Grafana, Loki |

---

## Матрица ролей

| Роль | Пользователи | Namespace | Разрешённые ресурсы | Разрешённые действия | Запрещено |
|------|-------------|-----------|--------------------|--------------------|-----------|
| `developer-sales` | dev-ivanov, dev-petrov | `sales` | pods, deployments, services, configmaps, logs | get, list, watch, create, update, patch | delete (pods/deployments), exec в prod, secrets |
| `developer-jku` | dev-sidorov, dev-kuznetsov | `jku` | pods, deployments, services, configmaps, logs | get, list, watch, create, update, patch | delete, exec, secrets |
| `ops-engineer` | ops-volkov | `sales`, `jku`, `data`, `infra` | pods, deployments, services, configmaps, secrets, persistentvolumeclaims | get, list, watch, update, patch, delete | create new namespaces, ClusterRole изменение |
| `data-engineer` | data-morozov | `data` | pods, deployments, services, configmaps, jobs, cronjobs | get, list, watch, create, update, patch, delete | secrets, exec в prod pods |
| `security-auditor` | sec-lebedev | `sales`, `jku`, `data`, `infra`, `monitoring` | pods, deployments, services, configmaps, networkpolicies, rolebindings, roles | get, list, watch | create, update, delete (любые ресурсы) |
| `monitoring-reader` | grafana-sa (ServiceAccount) | `monitoring`, `sales`, `jku`, `data` | pods, nodes, endpoints, services | get, list, watch | всё остальное |
| `cluster-admin-restricted` | admin-sokolov | все | все ресурсы | все действия | — (полный доступ с аудитом) |

---

## Детальное описание ролей

### developer-sales
**Назначение**: разработчики домена продаж (витрина, онлайн-тур, онлайн-сделка).

**Принцип минимальных привилегий**: могут просматривать логи и рестартовать поды для отладки,
но не могут удалять ресурсы в production и не имеют доступа к секретам (DB credentials, API keys).

### developer-jku
**Назначение**: разработчики домена ЖКУ (tenant-core, smart-home-service, partner-api-gateway).

**Дополнительное ограничение**: нет доступа к `sales` namespace — домены изолированы.

### ops-engineer
**Назначение**: инженер эксплуатации. Устраняет инциденты, управляет ресурсами кластера.

**Доступ к secrets**: только `get/list` (для диагностики), без возможности изменить.
Namespace `monitoring` — только read (не нужен write для эксплуатации приложений).

### data-engineer
**Назначение**: инженер данных. Управляет ETL-задачами в DWH.

**Изолирован** от сервисных namespace-ов `sales` и `jku` — принцип разделения обязанностей.

### security-auditor
**Назначение**: специалист по ИБ. Проводит аудит конфигурации кластера.

**Только чтение** по всему кластеру, включая network policies и role bindings.
Устраняет зафиксированную уязвимость: аудитор должен видеть все изменения (чеклист п. 5.4).

### monitoring-reader (ServiceAccount)
**Назначение**: технический аккаунт для Grafana/Prometheus — сбор метрик.

**ServiceAccount** вместо User: автоматическая ротация токена Kubernetes.

---

## Диаграмма доступа

```
Namespace:  sales          jku            data           infra      monitoring
            ─────────────────────────────────────────────────────────────────
dev-ivanov  RW (no sec)    ✗              ✗              ✗          ✗
dev-petrov  RW (no sec)    ✗              ✗              ✗          ✗
dev-sidorov ✗              RW (no sec)    ✗              ✗          ✗
dev-kuznetsov ✗            RW (no sec)    ✗              ✗          ✗
ops-volkov  RW+del         RW+del         RW+del         RW+del     R
data-morozov ✗             ✗              RW+del         ✗          ✗
sec-lebedev R              R              R              R          R
grafana-sa  R(pods)        R(pods)        R(pods)        ✗          RW
admin-sokolov  ALL          ALL            ALL            ALL        ALL
```
`R` = get/list/watch, `RW` = +create/update/patch, `del` = +delete, `✗` = нет доступа

---

## Соответствие требованиям безопасности

| Требование | Реализация |
|-----------|-----------|
| Принцип минимальных привилегий | Каждая роль ограничена своим namespace и набором verb |
| Изоляция по доменам | `developer-sales` и `developer-jku` не пересекаются |
| Нет доступа к secrets для разработчиков | Verb `get/list` для secrets исключён из developer-ролей |
| Аудитор видит всё | `security-auditor` — read-only по всем namespace-ам |
| Мониторинг через ServiceAccount | `monitoring-reader` — не человек, токен ротируется автоматически |
