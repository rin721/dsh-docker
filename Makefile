.PHONY: deploy update rebuild check doctor self-test stop user users remove-user build shell

deploy:
	./scripts/deploy.sh

update:
	./scripts/update.sh

rebuild:
	./scripts/rebuild.sh

check:
	./scripts/check.sh

doctor:
	./scripts/doctor.sh

self-test:
	./scripts/self-test.sh

stop:
	./scripts/stop.sh

user:
	./scripts/create-user.sh

users:
	./scripts/list-users.sh

remove-user:
	./scripts/remove-user.sh

build:
	DSH_IMAGE_MODE=build ./scripts/rebuild.sh

shell:
	docker compose exec dsh bash
