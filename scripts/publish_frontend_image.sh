#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <image-tag> [aws-region]" >&2
  exit 1
fi

image_tag="$1"
aws_region="${2:-${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}}"
project_name="ecs-bg-deployment"
repository_name="${project_name}-frontend-app"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

account_id="$(aws sts get-caller-identity --query Account --output text)"
registry="${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
repository_uri="${registry}/${repository_name}"

aws ecr describe-repositories \
  --region "${aws_region}" \
  --repository-names "${repository_name}" >/dev/null

aws ecr get-login-password --region "${aws_region}" \
  | docker login \
      --username AWS \
      --password-stdin "${registry}"

docker build \
  --platform linux/arm64 \
  --build-arg APP_NAME="${project_name}" \
  --build-arg APP_VERSION="${image_tag}" \
  --tag "${repository_uri}:${image_tag}" \
  "${repo_root}/app/frontend"

docker push "${repository_uri}:${image_tag}"

echo "Pushed ${repository_uri}:${image_tag}"
