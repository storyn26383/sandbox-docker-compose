.PHONY: init build start stop restart shell ssh logs reset-db herdr-relay-start herdr-relay-stop

-include .env
export

SANDBOX_SSH_PORT ?= 2222
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
GIT_USER_NAME := $(shell git config --get user.name)
GIT_USER_EMAIL := $(shell git config --get user.email)
SSH_OPTS = -p $(SANDBOX_SSH_PORT) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

HERDR_RELAY_PID := .data/herdr-relay.pid
HERDR_RELAY_LOG := .data/herdr-relay.log
HERDR_RELAY_PORT := 47123
# its agents are released when it stops; the name comes from docker-compose.yml
HERDR_RELAY_CONTAINER := sandbox-workspace

init: .env build
	git submodule update --init --recursive
	mkdir -p workspace .data/herdr

.env:
	cp .env.example .env

build:
	docker compose build $(filter-out build,$(MAKECMDGOALS))

start: herdr-relay-start
	docker compose up -d

stop: herdr-relay-stop
	docker compose down

# Host-side bridge so agents inside the container can report state to herdr; see herdr-relay.ts
herdr-relay-start:
	@mkdir -p $(dir $(HERDR_RELAY_PID))
	@if [ -f $(HERDR_RELAY_PID) ] && kill -0 $$(cat $(HERDR_RELAY_PID)) 2>/dev/null; then :; \
	else HERDR_RELAY_PORT=$(HERDR_RELAY_PORT) HERDR_RELAY_CONTAINER=$(HERDR_RELAY_CONTAINER) nohup bun herdr-relay.ts > $(HERDR_RELAY_LOG) 2>&1 & echo $$! > $(HERDR_RELAY_PID); fi

herdr-relay-stop:
	@if [ -f $(HERDR_RELAY_PID) ]; then kill $$(cat $(HERDR_RELAY_PID)) 2>/dev/null || true; rm -f $(HERDR_RELAY_PID); fi

restart: stop start

shell:
	docker compose exec -u sandbox -e HERDR_ENV -e HERDR_PANE_ID workspace bash

ssh:
	ssh $(SSH_OPTS) sandbox@localhost

logs:
	docker compose logs -f

reset-db:
	docker compose down
	rm -rf clickhouse/docker/.data/clickhouse .data/mysql .data/redis

# Swallow extra goals so flags like `make build -- --no-cache` forward to the recipe
%:
	@:
