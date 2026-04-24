# Sweptlock Infrastructure — Makefile
# Shortcuts for common Terragrunt + Docker operations.
# Usage: make <target>   (run from repo root)

ENV     ?= sandbox
REGION  ?= me-west1
PROJECT ?= cryptoshare-e5172
PREFIX  ?= swpt-mw1-$(ENV)

STACK_ROOT := regions/$(REGION)/$(ENV)
IMAGE_BASE := $(REGION)-docker.pkg.dev/$(PROJECT)/$(PREFIX)-registry/api

.PHONY: help init plan apply destroy \
        apply-networking apply-security apply-registry apply-database apply-compute \
        build push deploy \
        populate-secrets setup-cicd-sa bootstrap \
        ssh logs health

# ── Default ───────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Sweptlock Infrastructure"
	@echo ""
	@echo "  Bootstrap"
	@echo "    make bootstrap          Run once: create GCS bucket + enable APIs"
	@echo "    make setup-cicd-sa      Create GitHub CI service account"
	@echo ""
	@echo "  Terraform"
	@echo "    make init               terragrunt run --all init"
	@echo "    make plan               terragrunt run --all plan"
	@echo "    make apply              Apply all stacks (ordered by deps)"
	@echo "    make destroy            Destroy all stacks"
	@echo "    make apply-<module>     Apply single stack (networking|security|registry|database|compute)"
	@echo ""
	@echo "  Docker"
	@echo "    make build              Build docker image (linux/amd64)"
	@echo "    make push               Push image to Artifact Registry"
	@echo "    make deploy             build + push"
	@echo ""
	@echo "  Secrets"
	@echo "    make populate-secrets   Push all secrets to Secret Manager"
	@echo ""
	@echo "  VM"
	@echo "    make ssh                SSH into the API VM via IAP"
	@echo "    make logs               Tail container logs on VM"
	@echo "    make health             Curl the health endpoint"
	@echo ""
	@echo "  Options: ENV=$(ENV) REGION=$(REGION) PROJECT=$(PROJECT)"
	@echo ""

# ── Bootstrap ────────────────────────────────────────────────────────────────
bootstrap:
	./scripts/bootstrap.sh $(PROJECT) $(REGION) $(ENV)

setup-cicd-sa:
	./scripts/setup-cicd-sa.sh $(PROJECT)

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
apply-networking:
	cd $(STACK_ROOT)/networking && terragrunt apply -auto-approve

apply-security:
	cd $(STACK_ROOT)/security && terragrunt apply -auto-approve

apply-registry:
	cd $(STACK_ROOT)/registry && terragrunt apply -auto-approve

apply-database:
	cd $(STACK_ROOT)/database && terragrunt apply -auto-approve

apply-compute:
	cd $(STACK_ROOT)/compute && terragrunt apply -auto-approve

# ── Docker ───────────────────────────────────────────────────────────────────
ALADIN_BACKEND ?= $(HOME)/Desktop/PersonalGitProjects/Aladin/aladin-backend

build:
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet
	docker build \
		--platform linux/amd64 \
		-f $(ALADIN_BACKEND)/docker/Dockerfile \
		-t $(IMAGE_BASE):latest \
		$(ALADIN_BACKEND)

push:
	docker push $(IMAGE_BASE):latest

deploy: build push

# ── Secrets ──────────────────────────────────────────────────────────────────
populate-secrets:
	./scripts/populate-secrets.sh $(PROJECT)

# ── VM operations ────────────────────────────────────────────────────────────
VM_NAME := $(PREFIX)-api
VM_ZONE := $(REGION)-a

_vm_ip:
	@cd $(STACK_ROOT)/compute && terragrunt output -raw external_ip 2>/dev/null

ssh:
	gcloud compute ssh $(VM_NAME) \
		--zone=$(VM_ZONE) \
		--tunnel-through-iap \
		--project=$(PROJECT)

logs:
	gcloud compute ssh $(VM_NAME) \
		--zone=$(VM_ZONE) \
		--tunnel-through-iap \
		--project=$(PROJECT) \
		--command="docker logs sweptlock-api -f --tail=100"

health:
	@IP=$$(cd $(STACK_ROOT)/compute && terragrunt output -raw external_ip 2>/dev/null); \
	echo "GET http://$$IP:4000/health"; \
	curl -s http://$$IP:4000/health | jq .
