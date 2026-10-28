.PHONY: init init-omp-gateway build start stop restart shell logs reset-db herdr-relay-start herdr-relay-stop

-include .env
export

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
GIT_USER_NAME := $(shell git config --get user.name)
GIT_USER_EMAIL := $(shell git config --get user.email)

CLAUDE_JSON := .data/claude.json
OMP_GATEWAY_DATA := .data/omp-gateway
OMP_GATEWAY_CONFIG_DIRECTORY := /home/sandbox/.omp-gateway/config/omp-session-gateway
OMP_GATEWAY_STATE_DIRECTORY := /home/sandbox/.omp-gateway/state
HERDR_RELAY_PID := .data/herdr-relay.pid
HERDR_RELAY_LOG := .data/herdr-relay.log
HERDR_RELAY_PORT := 47123

init: .env build $(CLAUDE_JSON) $(OMP_GATEWAY_DATA)
	git submodule update --init --recursive
	mkdir -p workspace

.env:
	cp .env.example .env

$(CLAUDE_JSON):
	mkdir -p $(@D)
	echo {} > $@

$(OMP_GATEWAY_DATA):
	mkdir -p -m 700 $(OMP_GATEWAY_DATA)

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
	else HERDR_RELAY_PORT=$(HERDR_RELAY_PORT) nohup bun herdr-relay.ts > $(HERDR_RELAY_LOG) 2>&1 & echo $$! > $(HERDR_RELAY_PID); fi

herdr-relay-stop:
	@if [ -f $(HERDR_RELAY_PID) ]; then kill $$(cat $(HERDR_RELAY_PID)) 2>/dev/null || true; rm -f $(HERDR_RELAY_PID); fi

restart: stop start

shell:
	docker compose exec -u sandbox -e HERDR_ENV -e HERDR_PANE_ID workspace bash

init-omp-gateway: $(OMP_GATEWAY_DATA)
	docker compose exec -u sandbox -w /home/sandbox/omp-session-gateway \
		-e BUN_INSTALL_CACHE_DIR=/home/sandbox/.bun/install/cache workspace \
		sh -euc 'bun install --frozen-lockfile && bun run build'
	docker compose exec -T -u sandbox \
		-e OMP_GATEWAY_TEAM_DOMAIN -e OMP_GATEWAY_AUDIENCE -e OMP_GATEWAY_ORIGIN -e OMP_GATEWAY_ALLOWED_LOGINS \
		workspace sh -euc 'umask 077 \
			&& chmod 700 /home/sandbox/.omp-gateway \
			&& mkdir -p $(OMP_GATEWAY_CONFIG_DIRECTORY) $(OMP_GATEWAY_STATE_DIRECTORY) \
			&& jq -n -f /dev/stdin > $(OMP_GATEWAY_CONFIG_DIRECTORY)/config.json.tmp \
			&& mv $(OMP_GATEWAY_CONFIG_DIRECTORY)/config.json.tmp $(OMP_GATEWAY_CONFIG_DIRECTORY)/config.json' \
		< supervisor/omp-session-gateway-config.jq
	docker compose exec workspace supervisorctl restart omp-gateway

logs:
	docker compose logs -f

reset-db:
	docker compose down
	rm -rf clickhouse/docker/.data/clickhouse .data/mysql .data/redis

# Swallow extra goals so flags like `make build -- --no-cache` forward to the recipe
%:
	@:
