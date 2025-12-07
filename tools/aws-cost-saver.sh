#!/bin/bash
# tools/aws-cost-saver.sh
set -e

# === КОНФИГУРАЦИЯ ===
# Укажите ID вашего учебного аккаунта, чтобы скрипт отказался работать в другом месте
ALLOWED_ACCOUNT_ID="492613460415" # <--- ВСТАВЬТЕ СВОЙ ID (aws sts get-caller-identity)
REGIONS=("eu-central-1" "eu-north-1")
TAG_KEY="env" # Если есть теги, лучше фильтровать по ним (но для полной зачистки можно опустить)
# ====================

# 1. Проверка зависимостей
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Please install it."
  exit 1
fi

# 2. Проверка Аккаунта (Safety Check)
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ "$CURRENT_ACCOUNT" != "$ALLOWED_ACCOUNT_ID" ]; then
  echo "⛔ CRITICAL ERROR: Вы пытаетесь запустить скрипт в аккаунте $CURRENT_ACCOUNT."
  echo "   Разрешен только аккаунт: $ALLOWED_ACCOUNT_ID."
  echo "   Остановка."
  exit 1
fi

# 3. Подтверждение пользователя
echo "========================================================"
echo "⚠️  WARNING: ВЫ СОБИРАЕТЕСЬ УДАЛИТЬ РЕСУРСЫ В $CURRENT_ACCOUNT"
echo "   Регионы: ${REGIONS[*]}"
echo "   Будут удалены: Spot Fleets, EC2, NAT Gateways, EBS, EIP, IAM Roles (pattern: defaultUser_)"
echo "========================================================"
read -p "Вы уверены? Введите 'DESTROY' для продолжения: " confirm
if [ "$confirm" != "DESTROY" ]; then
  echo "Отмена."
  exit 0
fi

export AWS_PAGER=""

# ... (ДАЛЕЕ ВСТАВЛЯЕМ ЛОГИКУ УДАЛЕНИЯ ИЗ ПРЕДЫДУЩЕГО СКРИПТА) ...
# Я добавил только пару улучшений в логику ниже:

for REGION in "${REGIONS[@]}"; do
  echo ">>> Зачистка региона: $REGION"

  # Spot Fleets
  echo "Checking Spot Fleets..."
  # Используем --no-paginate для скорости
  spots=$(aws ec2 describe-spot-fleet-requests --region $REGION --query "SpotFleetRequestConfigs[?SpotFleetRequestState=='active'||SpotFleetRequestState=='submitted'].SpotFleetRequestId" --output text)
  if [ -n "$spots" ]; then
    aws ec2 cancel-spot-fleet-requests --region $REGION --terminate-instances --spot-fleet-request-ids $spots
    echo "   Deleted Spot Requests: $spots"
  fi

  # ... (Остальные ресурсы: Instances, NAT, Volumes, EIP - как в прошлом скрипте)
  # 2. EC2 Instances (Серверы)
  echo "  [2/6] Проверка EC2 Instances (Running/Stopped)..."
  instance_ids=$(aws ec2 describe-instances --region $REGION --filters "Name=instance-state-name,Values=running,stopped,stopping,pending" --query "Reservations[].Instances[].InstanceId" --output text)
  if [ -n "$instance_ids" ]; then
    echo "       Найдено: $instance_ids. Уничтожаем..."
    aws ec2 terminate-instances --region $REGION --instance-ids $instance_ids >/dev/null
  else
    echo "       Чисто."
  fi

  # 3. NAT Gateways (Самое дорогое в сети)
  echo "  [3/6] Проверка NAT Gateways..."
  nat_ids=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=state,Values=available,pending,failed" --query "NatGateways[].NatGatewayId" --output text)
  if [ -n "$nat_ids" ]; then
    for nat in $nat_ids; do
      echo "       Удаляем NAT: $nat (это может занять время)..."
      aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id $nat
    done
  else
    echo "       Чисто."
  fi

  # 4. Elastic IPs
  echo "  [4/6] Проверка Elastic IPs..."
  eip_ids=$(aws ec2 describe-addresses --region $REGION --query "Addresses[].AllocationId" --output text)
  if [ -n "$eip_ids" ]; then
    for eip in $eip_ids; do
      echo "       Освобождаем IP: $eip..."
      aws ec2 release-address --region $REGION --allocation-id $eip
    done
  else
    echo "       Чисто."
  fi

  # 5. Load Balancers (v2 / ALB/NLB)
  echo "  [5/6] Проверка Load Balancers..."
  lb_arns=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[].LoadBalancerArn" --output text)
  if [ -n "$lb_arns" ]; then
    for lb in $lb_arns; do
      echo "       Удаляем LB: $lb..."
      aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn $lb
    done
  else
    echo "       Чисто."
  fi

  # 6. EBS Volumes (Диски) - удаляем только доступные (отцепленные)
  echo "  [6/6] Проверка свободных дисков (Available Volumes)..."
  vol_ids=$(aws ec2 describe-volumes --region $REGION --filter "Name=status,Values=available" --query "Volumes[].VolumeId" --output text)
  if [ -n "$vol_ids" ]; then
    echo "       Найдено: $vol_ids. Удаляем..."
    for vol in $vol_ids; do
      aws ec2 delete-volume --region $REGION --volume-id $vol
    done
  else
    echo "       Чисто (или диски еще прицеплены к удаляемым серверам)."
  fi

  echo "--------------------------------------------------------"
done

# IAM Cleanup (Оставляем как было, это безопасно, так как ищет по паттерну defaultUser_)
echo ">>> Cleaning IAM..."
# IAM Cleanup (Global)
aws iam list-instance-profiles --output text --query "InstanceProfiles[?contains(InstanceProfileName, 'defaultUser_defaultId_')].InstanceProfileName" | tr '\t' '\n' | while read profile; do
  if [ -n "$profile" ]; then
    echo "   Del Profile: $profile"
    roles=$(aws iam get-instance-profile --instance-profile-name "$profile" --output text --query "InstanceProfile.Roles[].RoleName")
    for role in $roles; do aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role"; done
    aws iam delete-instance-profile --instance-profile-name "$profile"
  fi
done

aws iam list-roles --output text --query "Roles[?contains(RoleName, 'defaultUser_defaultId_')].RoleName" | tr '\t' '\n' | while read role; do
  if [ -n "$role" ]; then
    echo "   Del Role: $role"
    pols=$(aws iam list-attached-role-policies --role-name "$role" --output text --query "AttachedPolicies[].PolicyArn")
    for pol in $pols; do aws iam detach-role-policy --role-name "$role" --policy-arn "$pol"; done
    inlines=$(aws iam list-role-policies --role-name "$role" --output text --query "PolicyNames")
    for inline in $inlines; do aws iam delete-role-policy --role-name "$role" --policy-name "$inline"; done
    aws iam delete-role --role-name "$role"
  fi
done

aws iam list-policies --scope Local --output text --query "Policies[?contains(PolicyName, 'defaultUser_defaultId_')].Arn" | tr '\t' '\n' | while read arn; do
  if [ -n "$arn" ]; then
    echo "   Del Policy: $arn"
    versions=$(aws iam list-policy-versions --policy-arn "$arn" --output text --query "Versions[?!IsDefaultVersion].VersionId")
    for ver in $versions; do aws iam delete-policy-version --policy-arn "$arn" --version-id "$ver"; done
    aws iam delete-policy --policy-arn "$arn"
  fi
done

echo "========================================================"
echo "   ГОТОВО. ДЕНЬГИ В БЕЗОПАСНОСТИ. ОТДЫХАЙТЕ!   "
echo "   (Совет: запустите скрипт еще раз через 2 минуты, чтобы удалить диски,"
echo "    которые освободятся после выключения серверов)"
echo "========================================================"
