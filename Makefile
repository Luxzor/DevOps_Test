# Atajos para trabajar en local. Los workflows usan los mismos scripts.
#   make help
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
COMPOSE := docker compose -f simulation/docker-compose.yml
ENVS := dev staging prod

# Etiqueta de la imagen: el commit actual; con cambios sin commitear se marca como "dirty".
TAG ?= $(shell git rev-parse HEAD)$(shell git diff --quiet HEAD -- app || echo "-dirty$$(date +%s)")
VERSION := $(shell grep -m1 '^version' app/pyproject.toml | cut -d'"' -f2)

.PHONY: help
help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Instala las dependencias de desarrollo de la app
	pip install -r app/requirements-dev.txt

.PHONY: lint
lint: ## Lint, formato y tipos (como el CI)
	(cd app && ruff check . && ruff format --check . && python -m mypy)
	terraform fmt -check -recursive infra
	shellcheck -x -P scripts scripts/*.sh

.PHONY: test
test: ## Pruebas con cobertura (mínimo 80 %)
	cd app && python -m pytest --cov

.PHONY: run
run: ## Levanta la API en http://localhost:8000
	cd app && PYTHONPATH=src python -m uvicorn tasks_api.asgi:app --reload

.PHONY: sim-up
sim-up: ## Arranca las tres cuentas simuladas
	$(COMPOSE) up -d --wait

.PHONY: sim-down
sim-down: ## Detiene la simulación (conserva el estado)
	$(COMPOSE) down

.PHONY: sim-reset
sim-reset: ## Borra la simulación por completo (estado incluido)
	$(COMPOSE) down -v
	rm -rf infra/bootstrap/terraform.tfstate.d

.PHONY: bootstrap
bootstrap: ## Bootstrap de las tres cuentas (estado remoto, OIDC, roles)
	for env in $(ENVS); do AUTO_APPROVE=1 scripts/bootstrap.sh $$env; done

.PHONY: infra
infra: ## terraform apply en los tres ambientes
	for env in $(ENVS); do scripts/tf.sh $$env init >/dev/null && scripts/tf.sh $$env apply -auto-approve; done

.PHONY: image
image: ## Construye la imagen etiquetada con el commit
	docker build -t tasks-api:$(TAG) --build-arg GIT_SHA=$(TAG) --build-arg APP_VERSION=$(VERSION) app

.PHONY: deploy-local
deploy-local: image ## Recorre el pipeline de CD en local: dev, staging (E2E) y prod
	scripts/publish-image.sh dev tasks-api:$(TAG) $(TAG)
	scripts/deploy.sh dev $(TAG)
	scripts/promote-image.sh dev staging $(TAG)
	scripts/deploy.sh staging $(TAG)
	scripts/e2e-test.sh staging
	scripts/promote-image.sh staging prod $(TAG)
	scripts/deploy.sh prod $(TAG)
	scripts/versions.sh

.PHONY: versions
versions: ## Qué versión corre en cada ambiente
	scripts/versions.sh
