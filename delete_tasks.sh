#!/bin/bash

set -euo pipefail

export AWS_PAGER=""

REGION="us-east-1"
INSTANCE_NAME_TAG="DemoEC2"
DB_INSTANCE_IDENTIFIER="demo-rds-instance"
LAMBDA_FUNCTION_NAME="demo-lambda"
BUDGET_NAME="demo-budget"
ROLE_NAME="LambdaBasicExecutionRole"

echo "🗑️ Eliminando RDS..."
aws rds delete-db-instance \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --skip-final-snapshot \
  --region "$REGION"

echo "⏳ Esperando a que RDS se elimine completamente..."
aws rds wait db-instance-deleted \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --region "$REGION"
echo "✅ RDS eliminada."

echo "🗑️ Eliminando función Lambda..."
aws lambda delete-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$REGION"
echo "✅ Lambda eliminada."

echo "🗑️ Eliminando instancia EC2 con etiqueta Name=$INSTANCE_NAME_TAG..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME_TAG" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text --region "$REGION")

if [ -z "$INSTANCE_IDS" ]; then
  echo "No se encontraron instancias EC2 con esa etiqueta."
else
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION"
  echo "⏳ Esperando a que las instancias EC2 se terminen..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
  echo "✅ Instancias EC2 eliminadas."
fi

echo "🗑️ Eliminando presupuesto..."
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
aws budgets delete-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" --region "$REGION"
echo "✅ Presupuesto eliminado."

echo "🗑️ Eliminando role IAM $ROLE_NAME..."
# Primero desanexar políticas
POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[].PolicyArn" --output text || echo "")

if [ -n "$POLICIES" ]; then
  for policy in $POLICIES; do
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy"
  done
fi

# Luego eliminar el role
aws iam delete-role --role-name "$ROLE_NAME" || echo "Role IAM $ROLE_NAME no existe o ya eliminado."

echo "✅ Role IAM eliminado."

echo "🧹 Limpieza completa."
