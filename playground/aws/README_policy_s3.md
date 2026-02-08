#Для ограничения доступа строго одним бакетом стандартные политики AWS (типа `AmazonS3FullAccess`) не подходят, так как они дают доступ ко **всем** бакетам.

Вам нужно создать **Custom Inline Policy** (встроенную политику) для пользователя `your-user`. Это делается в три шага: очистка, создание JSON-файла и применение.

### Шаг 1. Отзовите полные права (если уже выдали)

Если вы ранее выполнили команду `attach-user-policy` с `AmazonS3FullAccess`, сначала заберите эти права, иначе новая ограничивающая политика не будет иметь смысла (разрешающие права суммируются).

```bash
aws iam detach-user-policy \
    --user-name your-user \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --profile golddragon
```

### Шаг 2. Создайте файл политики

Политика должна разрешать действия с _самим бакетом_ (чтобы видеть список файлов) и с _объектами внутри него_ (чтобы читать/писать).

Создайте файл `s3-limit.json` (например, через `nvim s3-limit.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListingOfBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::cks-storage-yourbucket"]
    },
    {
      "Sid": "AllowAllActionsInBucket",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::cks-storage-yourbucket/*"]
    }
  ]
}
```

_Обратите внимание: `Resource` указывается дважды. Один раз для бакета (без `/_`), второй раз для содержимого (с `/_`). Это критично._

### Шаг 3. Примените политику (Inline Policy)

Используйте команду `put-user-policy`. Она "вшивает" этот JSON прямо в пользователя, не создавая отдельный объект политики в аккаунте (что удобно для точечных прав).

```bash
aws iam put-user-policy \
    --user-name your-user \
    --policy-name CksStorageOnlyAccess \
    --policy-document file://s3-limit.json \
    --profile golddragon
```

### Шаг 4. Проверка (Важный нюанс)

Теперь поведение CLI для пользователя `your-user` изменится.

1.  **Глобальный список бакетов (FAIL):**

    ```bash
    aws s3 ls --profile your-user
    ```

    _Результат:_ `AccessDenied`. Это **нормально**, так как мы не дали права `s3:ListAllMyBuckets`. Пользователь не должен знать о существовании других бакетов.

2.  **Доступ к конкретному бакету (SUCCESS):**

    ```bash
    aws s3 ls s3://cks-storage-yourbucket --profile your-user
    ```

    _Результат:_ Список файлов.

3.  **Попытка доступа к чужому бакету (FAIL):**

    ```bash
    aws s3 ls s3://another-bucket --profile your-user
    ```

    _Результат:_ `AccessDenied`.

### Резюме

Вы реализовали принцип **Least Privilege**. Пользователь `your-user` теперь работает как "в туннеле": он не видит ничего вокруг, но имеет полный контроль внутри `cks-storage-yourbucket`. READMI_policy_s3.md
