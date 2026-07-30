# Sweptlock Infrastructure — Makefile
# Shortcuts for common Terragrunt + Cloud Run operations.
# Usage: make <target> [ENV=dev]

ENV     ?= dev
REGION  ?= me-west1
PROJECT ?= sweptlock-dev-844f2
PREFIX  ?= swpt-mw1-$(ENV)

STACK_ROOT := regions/$(REGION)/$(ENV)
IMAGE_BASE := $(REGION)-docker.pkg.dev/$(PROJECT)/$(PREFIX)-registry/api
SERVICE    := $(PREFIX)-api

# Source path of the backend (on WSL)
BACKEND_DIR ?= /mnt/c/Users/tomer/Desktop/PersonalGitProjects/Sweptlock/backend

.PHONY: help preflight init plan apply destroy \
        apply-security apply-registry apply-networking apply-database \
        apply-deploy-engine apply-deploy-platform apply-cloud-run apply-platform \
        build push deploy \
        populate-secrets \
        logs health

# ── Default ───────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Sweptlock Infrastructure  (ENV=$(ENV)  PROJECT=$(PROJECT))"
	@echo ""
	@echo "  Bootstrap"
	@echo "    make bootstrap ENV=dev     Run once: create GCS bucket + WIF + SAs"
	@echo ""
	@echo "  Terraform (all stacks)"
	@echo "    make preflight             Read-only pre-apply gate: versions, auth, project, state bucket, runner image"
	@echo "    make init                  terragrunt run --all init"
	@echo "    make plan                  terragrunt run --all plan"
	@echo "    make apply                 Apply all stacks in dependency order"
	@echo "    make destroy               Destroy all stacks"
	@echo ""
	@echo "  Terraform (single stack)"
	@echo "    make apply-security"
	@echo "    make apply-registry"
	@echo "    make apply-networking"
	@echo "    make apply-database"
	@echo "    make apply-deploy-engine"
	@echo "    make apply-deploy-platform"
	@echo "    make apply-cloud-run"
	@echo "    make apply-platform"
	@echo ""
	@echo "  Docker (manual push)"
	@echo "    make build                 Build linux/amd64 image"
	@echo "    make push                  Push image to Artifact Registry"
	@echo "    make deploy                build + push + gcloud run deploy"
	@echo ""
	@echo "  Secrets"
	@echo "    make populate-secrets      Push app secrets from .env into Secret Manager"
	@echo ""
	@echo "  Operations"
	@echo "    make logs                  Tail Cloud Run logs"
	@echo "    make health                Curl Cloud Run health endpoint"
	@echo ""

# ── Bootstrap ────────────────────────────────────────────────────────────────
bootstrap:
	./scripts/bootstrap.sh $(ENV)

# ── Preflight ────────────────────────────────────────────────────────────────
# Read-only gate before any local apply. Catches the failure modes that have
# actually burned applies: version-pin skew, expired auth, wrong ambient
# project, unreachable state bucket, missing runner image, half-run bootstrap.
preflight:
	./scripts/preflight.sh $(ENV)

# ── Terraform: all stacks ────────────────────────────────────────────────────
init:
	cd $(STACK_ROOT) && terragrunt run --all init --non-interactive

plan:
	cd $(STACK_ROOT) && terragrunt run --all plan --non-interactive

apply:
	cd $(STACK_ROOT) && terragrunt run --all apply --non-interactive

destroy:
	cd $(STACK_ROOT) && terragrunt run --all destroy --non-interactive

# ── Terraform: individual stacks ─────────────────────────────────────────────
apply-security:
	cd $(STACK_ROOT)/security && terragrunt apply -auto-approve

apply-registry:
	cd $(STACK_ROOT)/registry && terragrunt apply -auto-approve

apply-networking:
	cd $(STACK_ROOT)/networking && terragrunt apply -auto-approve

apply-database:
	cd $(STACK_ROOT)/database && terragrunt apply -auto-approve

apply-deploy-engine:
	cd $(STACK_ROOT)/deploy-identity-engine && terragrunt apply -auto-approve

apply-deploy-platform:
	cd $(STACK_ROOT)/deploy-identity-platform && terragrunt apply -auto-approve

apply-cloud-run:
	cd $(STACK_ROOT)/cloud-run && terragrunt apply -auto-approve

apply-platform:
	cd $(STACK_ROOT)/platform && terragrunt apply -auto-approve

# ── Docker (manual builds — CI uses GitHub Actions) ──────────────────────────
build:
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet
	docker build \
		--platform linux/amd64 \
		-f $(BACKEND_DIR)/docker/Dockerfile \
		-t $(IMAGE_BASE):latest \
		$(BACKEND_DIR)

push:
	docker push $(IMAGE_BASE):latest

deploy: build push
	gcloud run deploy $(SERVICE) \
		--image=$(IMAGE_BASE):latest \
		--region=$(REGION) \
		--project=$(PROJECT) \
		--quiet

# ── Secrets ──────────────────────────────────────────────────────────────────
populate-secrets:
	./scripts/populate-secrets.sh $(PROJECT)

# ── Cloud Run operations ─────────────────────────────────────────────────────
logs:
	gcloud run services logs tail $(SERVICE) \
		--project=$(PROJECT) \
		--region=$(REGION)

health:
	@URL=$$(gcloud run services describe $(SERVICE) \
		--region=$(REGION) --project=$(PROJECT) \
		--format='value(status.url)'); \
	echo "GET $$URL/health"; \
	curl -sf "$$URL/health" | jq .
