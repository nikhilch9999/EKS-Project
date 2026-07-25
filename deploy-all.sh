#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
CLUSTER_NAME="demo-cluster"
KEY_NAME="node-key-pair"
STACK_NAME="eks-cluster-stack"
VPC_ID="vpc-0ea4f485f80d74d31"
SUBNETS="subnet-0ffe1fa436f41ee03,subnet-0e67b279e8c52d221"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() {
  echo "[deploy-all] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

require_cmd aws
require_cmd kubectl
require_cmd eksctl

log "Ensuring AWS CLI region is set"
export AWS_DEFAULT_REGION="$REGION"

log "Checking whether cluster exists"
if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  log "Creating EKS cluster from cluster.yaml"
  eksctl create cluster -f cluster.yaml
fi

log "Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

log "Creating EC2 key pair if needed"
if ! aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_NAME.pem"
  chmod 600 "$KEY_NAME.pem"
fi

log "Creating worker-node CloudFormation stack if needed"
if ! aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  aws cloudformation create-stack \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2022-12-23/amazon-eks-nodegroup.yaml \
    --parameters "[{\"ParameterKey\":\"ClusterName\",\"ParameterValue\":\"$CLUSTER_NAME\"},{\"ParameterKey\":\"ClusterControlPlaneSecurityGroup\",\"ParameterValue\":\"$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)\"},{\"ParameterKey\":\"NodeGroupName\",\"ParameterValue\":\"eks-demo-node\"},{\"ParameterKey\":\"NodeImageIdSSMParam\",\"ParameterValue\":\"/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2\"},{\"ParameterKey\":\"NodeInstanceType\",\"ParameterValue\":\"t3.medium\"},{\"ParameterKey\":\"KeyName\",\"ParameterValue\":\"$KEY_NAME\"},{\"ParameterKey\":\"VpcId\",\"ParameterValue\":\"$VPC_ID\"},{\"ParameterKey\":\"Subnets\",\"ParameterValue\":\"$SUBNETS\"},{\"ParameterKey\":\"NodeAutoScalingGroupDesiredCapacity\",\"ParameterValue\":\"2\"},{\"ParameterKey\":\"NodeAutoScalingGroupMaxSize\",\"ParameterValue\":\"3\"},{\"ParameterKey\":\"NodeAutoScalingGroupMinSize\",\"ParameterValue\":\"1\"}]" \
    --capabilities CAPABILITY_IAM
fi

log "Waiting for worker-node stack to complete"
aws cloudformation wait stack-create-complete --region "$REGION" --stack-name "$STACK_NAME"

log "Retrieving worker role ARN"
NODE_ROLE_ARN="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceRole`].OutputValue' --output text)"

if [[ -z "$NODE_ROLE_ARN" || "$NODE_ROLE_ARN" == "None" ]]; then
  NODE_ROLE_ARN="arn:aws:iam::$((aws sts get-caller-identity --query Account --output text)):role/${STACK_NAME}-NodeInstanceRole"
fi

log "Writing aws-auth ConfigMap with node role"
TMP_AUTH="$(mktemp)"
trap 'rm -f "$TMP_AUTH"' EXIT
sed "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|" aws-auth-cm.yaml > "$TMP_AUTH"
cp "$TMP_AUTH" aws-auth-cm.yaml

log "Applying aws-auth ConfigMap"
kubectl apply -f aws-auth-cm.yaml

log "Waiting for worker nodes to appear"
for _ in $(seq 1 30); do
  NODE_COUNT="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$NODE_COUNT" -gt 0 ]]; then
    break
  fi
  sleep 20
 done

log "Applying application manifests"
kubectl apply -f app.yaml

log "Done. Run: kubectl get nodes && kubectl get pods -A"
