#!/bin/bash

set -euo pipefail

# Desactivar paginador AWS CLI para que no pare en ningún momento
export AWS_PAGER=""

REGION="us-east-1"

echo "📊 Creando presupuesto (budget)..."
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget '{
    "BudgetName": "demo-budget",
    "BudgetLimit": {
      "Amount": "1.00",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --region "$REGION" > /dev/null

echo "✅ Presupuesto creado."

echo "📦 Creando instancia EC2 mínima..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --region "$REGION" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DemoEC2}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

if [ -z "$INSTANCE_ID" ]; then
  echo "❌ Error creando EC2. Abortando."
  exit 1
fi

echo "🔌 Esperando a que la instancia EC2 esté en estado 'running'..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
echo "✅ EC2 creada: $INSTANCE_ID"

echo "🧠 Creando función Lambda básica..."

# Crear archivo lambda_function.py temporal
cat <<EOF > lambda_function.py
def lambda_handler(event, context):
    return {"message": "Hello from Lambda"}
EOF

# Crear archivo zip
zip -q lambda_function.zip lambda_function.py

ROLE_NAME="LambdaBasicExecutionRole"

# Intentar obtener ARN del role si ya existe
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null || echo "")

if [ -z "$ROLE_ARN" ]; then
  echo "🔐 Creando role IAM para Lambda..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' > /dev/null

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null

  echo "⏳ Esperando propagación del role IAM (15s)..."
  sleep 15

  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
fi

# Crear función Lambda (si ya existe dará error, puedes agregar lógica para actualizar si quieres)
aws lambda create-function \
  --function-name demo-lambda \
  --runtime python3.9 \
  --role "$ROLE_ARN" \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --region "$REGION" > /dev/null

echo "✅ Lambda creada."

echo "🗃️  Creando RDS mínima (db.t3.micro)..."
aws rds create-db-instance \
  --db-instance-identifier demo-rds-instance \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --allocated-storage 20 \
  --master-username adminuser \
  --master-user-password MySecurePass123! \
  --no-publicly-accessible \
  --region "$REGION" > /dev/null

echo "⏳ Esperando a que RDS esté disponible (esto puede tardar varios minutos)..."
aws rds wait db-instance-available \
  --db-instance-identifier demo-rds-instance \
  --region "$REGION"
echo "✅ RDS creada."

echo "🎉 Todo creado correctamente."
