.PHONY: init build start stop restart shell logs reset

-include .env
export

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
GIT_USER_NAME := $(shell git config --get user.name)
GIT_USER_EMAIL := $(shell git config --get user.email)

init: .env build .data/claude.json .data/codex/config.toml
	git submodule update --init --recursive
	mkdir -p workspace

.env:
	cp .env.example .env

.data/claude.json:
	mkdir -p .data
	echo {} > .data/claude.json

.data/codex/config.toml:
	mkdir -p .data/codex
	echo 'cli_auth_credentials_store = "file"' > .data/codex/config.toml

build:
	docker compose build

start:
	docker compose up -d

stop:
	docker compose down

restart: stop start

shell:
	docker compose exec -u sandbox workspace bash

logs:
	docker compose logs -f

reset:
	docker compose down
	rm -rf clickhouse/docker/.data/clickhouse .data/mysql .data/redis
