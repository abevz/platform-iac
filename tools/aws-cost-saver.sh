#!/bin/bash
# tools/aws-cost-saver.sh
set -e

# === CONFIGURATION ===
# Specify your learning account ID so the script refuses to run elsewhere
ALLOWED_ACCOUNT_ID="492613460415"
REGIONS=("eu-central-1" "eu-north-1")
TAG_KEY="env" # If tags exist, filter by them (but for full cleanup can be omitted)
# ====================

# 1. Check dependencies
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Please install it."
  exit 1
fi

# 2. Account verification (Safety Check)
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ "$CURRENT_ACCOUNT" != "$ALLOWED_ACCOUNT_ID" ]; then
  echo "CRITICAL ERROR: You are trying to run the script in account $CURRENT_ACCOUNT."
  echo "   Only allowed account: $ALLOWED_ACCOUNT_ID."
  echo "   Stopping."
  exit 1
fi

# 3. User confirmation
echo "========================================================"
echo "WARNING: YOU ARE ABOUT TO DELETE RESOURCES IN $CURRENT_ACCOUNT"
echo "   Regions: ${REGIONS[*]}"
echo "   Will delete: Spot Fleets, EC2, NAT Gateways, EBS, EIP, IAM Roles (pattern: defaultUser_)"
echo "========================================================"
read -p "Are you sure? Type 'DESTROY' to continue: " confirm
if [ "$confirm" != "DESTROY" ]; then
  echo "Cancelled."
  exit 0
fi

export AWS_PAGER=""

for REGION in "${REGIONS[@]}"; do
  echo ">>> Cleaning region: $REGION"

  # Spot Fleets
  echo "Checking Spot Fleets..."
  spots=$(aws ec2 describe-spot-fleet-requests --region $REGION --query "SpotFleetRequestConfigs[?SpotFleetRequestState=='active'||SpotFleetRequestState=='submitted'].SpotFleetRequestId" --output text)
  if [ -n "$spots" ]; then
    aws ec2 cancel-spot-fleet-requests --region $REGION --terminate-instances --spot-fleet-request-ids $spots
    echo "   Deleted Spot Requests: $spots"
  fi

  # 2. EC2 Instances
  echo "  [2/6] Checking EC2 Instances (Running/Stopped)..."
  instance_ids=$(aws ec2 describe-instances --region $REGION --filters "Name=instance-state-name,Values=running,stopped,stopping,pending" --query "Reservations[].Instances[].InstanceId" --output text)
  if [ -n "$instance_ids" ]; then
    echo "       Found: $instance_ids. Terminating..."
    aws ec2 terminate-instances --region $REGION --instance-ids $instance_ids >/dev/null
  else
    echo "       Clean."
  fi

  # 3. NAT Gateways (Most expensive network resource)
  echo "  [3/6] Checking NAT Gateways..."
  nat_ids=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=state,Values=available,pending,failed" --query "NatGateways[].NatGatewayId" --output text)
  if [ -n "$nat_ids" ]; then
    for nat in $nat_ids; do
      echo "       Deleting NAT: $nat (this may take time)..."
      aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id $nat
    done
  else
    echo "       Clean."
  fi

  # 4. Elastic IPs
  echo "  [4/6] Checking Elastic IPs..."
  eip_ids=$(aws ec2 describe-addresses --region $REGION --query "Addresses[].AllocationId" --output text)
  if [ -n "$eip_ids" ]; then
    for eip in $eip_ids; do
      echo "       Releasing IP: $eip..."
      aws ec2 release-address --region $REGION --allocation-id $eip
    done
  else
    echo "       Clean."
  fi

  # 5. Load Balancers (v2 / ALB/NLB)
  echo "  [5/6] Checking Load Balancers..."
  lb_arns=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[].LoadBalancerArn" --output text)
  if [ -n "$lb_arns" ]; then
    for lb in $lb_arns; do
      echo "       Deleting LB: $lb..."
      aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn $lb
    done
  else
    echo "       Clean."
  fi

  # 6. EBS Volumes - delete only available (detached)
  echo "  [6/6] Checking available volumes (Available Volumes)..."
  vol_ids=$(aws ec2 describe-volumes --region $REGION --filter "Name=status,Values=available" --query "Volumes[].VolumeId" --output text)
  if [ -n "$vol_ids" ]; then
    echo "       Found: $vol_ids. Deleting..."
    for vol in $vol_ids; do
      aws ec2 delete-volume --region $REGION --volume-id $vol
    done
  else
    echo "       Clean (or volumes still attached to instances being deleted)."
  fi

  echo "--------------------------------------------------------"
done

# IAM Cleanup (Global - searches by pattern defaultUser_)
echo ">>> Cleaning IAM..."
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
echo "   DONE. YOUR MONEY IS SAFE. RELAX!   "
echo "   (Tip: run the script again in 2 minutes to delete volumes"
echo "    that will become available after instances shut down)"
echo "========================================================"
