# README_quotas.md

Для проверки квот (Service Quotas) быстрее и надежнее всего использовать **AWS CLI** с профилем администратора (`golddragon`), так как в консоли поиск нужной строки среди сотен квот может занять много времени.

Квоты привязаны к **региону**. Если эмулятор будет работать в Стокгольме (`eu-north-1`), проверять нужно именно там.

### Шаг 1. Проверка текущих значений (CLI)

В AWS у каждой квоты есть уникальный `QuotaCode`.

- **L-1216C47A** — Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances.
- **L-34B43A08** — All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests.

Выполните эту команду, чтобы увидеть оба значения сразу. Замените регион на тот, где планируете запускать эмулятор (например, `eu-north-1` или `eu-central-1`):

```bash
aws service-quotas list-service-quotas \
    --service-code ec2 \
    --region eu-north-1 \
    --profile golddragon \
    --query "Quotas[?QuotaCode=='L-1216C47A' || QuotaCode=='L-34B43A08'].{Name:QuotaName, Value:Value, Code:QuotaCode}" \
    --output table
```

**Ожидаемый результат:**
Вы увидите таблицу с колонкой `Value`.

- Если `Value` \>= **40** — все отлично.
- Если `Value` = **5** (или другое число меньше 40) — нужно запрашивать увеличение.

---

### Шаг 2. Запрос на увеличение квот (если значений не хватает)

Если проверка показала дефолтные значения (5), отправьте запрос на увеличение прямо из терминала. Это создаст тикет в поддержку AWS (обычно одобряют автоматически за 15-30 минут, но иногда занимает до 24 часов).

**1. Увеличить On-Demand (обычные серверы) до 40:**

```bash
aws service-quotas request-service-quota-increase \
    --service-code ec2 \
    --quota-code L-1216C47A \
    --desired-value 40 \
    --region eu-north-1 \
    --profile golddragon
```

**2. Увеличить Spot (дешевые прерываемые серверы) до 40:**

```bash
aws service-quotas request-service-quota-increase \
    --service-code ec2 \
    --quota-code L-34B43A08 \
    --desired-value 40 \
    --region eu-north-1 \
    --profile golddragon
```

---

### Шаг 3. Как проверить статус заявки

После отправки запроса вы можете следить за его статусом:

```bash
aws service-quotas list-requested-service-quota-change-history-by-quota \
    --service-code ec2 \
    --quota-code L-1216C47A \
    --region eu-north-1 \
    --profile golddragon \
    --query "RequestedQuotas[0].{Status:Status, NewValue:DesiredValue}"
```

- **Status: CASE_OPENED** — заявка на рассмотрении.
- **Status: APPROVED** — готово, можно запускать эмулятор.

### Важное примечание

Новые аккаунты AWS часто находятся в "песочнице" и могут получить отказ при попытке резко увеличить квоты (с 5 до 40).
Если запрос отклонят (Denied), вам придет email. В этом случае нужно будет ответить на тикет в поддержке, написав примерно следующее: _"I am preparing for an exam using a certified emulator aiming to deploy a Kubernetes cluster lab. This is for educational purposes, instances will be short-lived."_
