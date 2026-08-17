.PHONY: deploy update rebuild check doctor self-test prepare-release repair-permissions check-image fix-home migrate-home backup stop user users remove-user build shell

deploy:
	bash ./scripts/deploy.sh

update:
	bash ./scripts/update.sh

rebuild:
	bash ./scripts/rebuild.sh

check:
	bash ./scripts/check.sh

doctor:
	bash ./scripts/doctor.sh

self-test:
	bash ./scripts/self-test.sh

prepare-release:
	bash ./scripts/prepare-release.sh

repair-permissions:
	bash ./scripts/repair-permissions.sh

fix-home:
	bash ./scripts/fix-home-permissions.sh

migrate-home:
	bash ./scripts/migrate-home-state.sh

backup:
	bash ./scripts/backup.sh

check-image:
	bash ./scripts/check-image.sh

stop:
	bash ./scripts/stop.sh

user:
	bash ./scripts/create-user.sh

users:
	bash ./scripts/list-users.sh

remove-user:
	bash ./scripts/remove-user.sh

build:
	DSH_IMAGE_MODE=build bash ./scripts/rebuild.sh

shell:
	docker compose exec dsh bash
