.PHONY: init user deploy rebuild update check logs stop edge-up edge-down shell

init:
	./scripts/init-runtime.sh

user:
	./scripts/create-user.sh

deploy:
	./scripts/deploy.sh

rebuild:
	./scripts/rebuild.sh

update:
	./scripts/update.sh

check:
	./scripts/check.sh

logs:
	docker compose logs -f --tail=200

stop:
	./scripts/stop.sh

edge-up:
	./scripts/edge-up.sh

edge-down:
	./scripts/edge-down.sh

shell:
	docker compose exec dsh bash
