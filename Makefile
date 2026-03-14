# プロジェクト名とアプリ名
PROJECT_NAME := ecs-bg-deployment
APP_NAME := frontend-app
APP_DIR := app/frontend

# AWS / Docker の実行設定
AWS_REGION ?= ap-northeast-1
AWS_PROFILE ?=
IMAGE_TAG ?=

DOCKER ?= docker
DOCKER_PLATFORM ?= linux/arm64
AWS_PROFILE_FLAG := $(if $(AWS_PROFILE),--profile $(AWS_PROFILE),)
AWS_CLI := AWS_PAGER= aws $(AWS_PROFILE_FLAG)
# 明示指定がなければ、AWS CLI の認証情報から Account ID を取得する
AWS_ACCOUNT_ID ?= $(shell $(AWS_CLI) sts get-caller-identity --query Account --output text 2>/dev/null)

# ECR に push するイメージ URI
ECR_REPOSITORY_NAME := $(PROJECT_NAME)-$(APP_NAME)
IMAGE_REPOSITORY_BASE := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
IMAGE_URI := $(IMAGE_REPOSITORY_BASE)/$(ECR_REPOSITORY_NAME):$(IMAGE_TAG)

.PHONY: help docker-login build-image push-image release-image print-image-uri

# 利用できるターゲットを表示する
# e.g. make help
help:
		@printf '%s\n' \
			'Available targets:' \
			'  make docker-login [AWS_REGION=ap-northeast-1]' \
			'  make build-image IMAGE_TAG=v1' \
			'  make push-image IMAGE_TAG=v1' \
			'  make release-image IMAGE_TAG=v1' \
			'  make print-image-uri IMAGE_TAG=v1' \
			'' \
			'Account ID is resolved from aws sts by default.' \
			'You can override it with AWS_ACCOUNT_ID=123456789012 if needed.'

# ECR にログインする
# e.g. make docker-login
docker-login: .require-aws-account
	$(AWS_CLI) ecr get-login-password --region $(AWS_REGION) | $(DOCKER) login --username AWS --password-stdin $(IMAGE_REPOSITORY_BASE)

# frontend アプリの Docker イメージをビルドする
# e.g. make build-image IMAGE_TAG=v1
build-image: .require-aws-account .require-image-tag
	$(DOCKER) build \
		--platform $(DOCKER_PLATFORM) \
		--build-arg APP_NAME=$(PROJECT_NAME) \
		--build-arg APP_VERSION=$(IMAGE_TAG) \
		-t $(IMAGE_URI) \
		-f $(APP_DIR)/Dockerfile \
		$(APP_DIR)

# frontend アプリの Docker イメージを ECR に push する
# e.g. make push-image IMAGE_TAG=v1
push-image: .require-aws-account .require-image-tag
	$(AWS_CLI) ecr describe-repositories --region $(AWS_REGION) --repository-names $(ECR_REPOSITORY_NAME) >/dev/null
	$(DOCKER) push $(IMAGE_URI)

# ECR ログイン、Docker build、ECR push をまとめて実行する
# e.g. make release-image IMAGE_TAG=v1
release-image: docker-login build-image push-image

# build / push 対象のイメージ URI を表示する
# e.g. make print-image-uri IMAGE_TAG=v1
print-image-uri: .require-aws-account .require-image-tag
	@echo $(IMAGE_URI)

.PHONY: .require-aws-account .require-image-tag

.require-aws-account:
	@if [ -z "$(AWS_ACCOUNT_ID)" ]; then \
		echo "AWS_ACCOUNT_ID を自動取得できませんでした。AWS 認証情報を設定するか、明示的に指定してください。" >&2; \
		exit 1; \
	fi

.require-image-tag:
	@if [ -z "$(IMAGE_TAG)" ]; then \
		echo "IMAGE_TAG が未設定です。例: make release-image IMAGE_TAG=v1" >&2; \
		exit 1; \
	fi
