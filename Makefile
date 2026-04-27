.PHONY: init start stop restart shell logs reset

init:
	git submodule update --init --recursive
	test -f .env || cp .env.example .env
	docker compose build

start:
	docker compose up -d

stop:
	docker compose down

restart: stop start

shell:
	docker compose exec dev bash

logs:
	docker compose logs -f

reset:
	docker compose down -v
	rm -rf golden-clickhouse/docker/.data/clickhouse
