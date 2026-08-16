.PHONY: deploy update rebuild check doctor self-test stop user users remove-user edge-up edge-down

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

edge-up:
	./scripts/edge-up.sh

edge-down:
	./scripts/edge-down.sh
