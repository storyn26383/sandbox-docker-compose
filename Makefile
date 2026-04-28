.PHONY: init start stop restart shell logs reset ssh tunnel

-include .env
export

SANDBOX_SSH_PORT ?= 2222
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
SSH_OPTS = -p $(SANDBOX_SSH_PORT) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

init:
	git submodule update --init --recursive
	test -f .env || cp .env.example .env
	mkdir -p docker/.data/coding
	docker compose build

start:
	docker compose up -d

stop:
	docker compose down

restart: stop start

shell:
	docker compose exec -u sandbox dev bash

logs:
	docker compose logs -f

reset:
	docker compose down
	rm -rf clickhouse/docker/.data/clickhouse docker/.data/mysql docker/.data/redis

ssh:
	ssh $(SSH_OPTS) sandbox@localhost

tunnel:
	ssh $(SSH_OPTS) -N \
		-L 13306:mysql:3306 \
		-L 16379:redis:6379 \
		-L 18123:clickhouse:8123 \
		-L 19000:clickhouse:9000 \
		-L 28123:clickhouse-testing:8123 \
		-L 29000:clickhouse-testing:9000 \
		sandbox@localhost
