.PHONY: deploy local domain-http domain-https update rebuild check doctor self-test stop user users remove-user set-mode edge-up edge-down shell

deploy:
	./scripts/deploy.sh

local:
	./scripts/deploy.sh local

domain-http:
	@echo "用法: make domain-http DOMAIN=dsh.example.com"
	@test -n "$(DOMAIN)"
	./scripts/deploy.sh domain-http "$(DOMAIN)"

domain-https:
	@echo "用法: make domain-https DOMAIN=dsh.example.com EMAIL=admin@example.com"
	@test -n "$(DOMAIN)"
	@test -n "$(EMAIL)"
	./scripts/deploy.sh domain-https "$(DOMAIN)" "$(EMAIL)"

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

set-mode:
	@echo "Use ./scripts/set-mode.sh local|domain-http|domain-https ..."

edge-up:
	./scripts/edge-up.sh

edge-down:
	./scripts/edge-down.sh

shell:
	docker compose exec dsh bash
