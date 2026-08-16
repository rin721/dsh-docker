.PHONY: deploy local domain-http domain-https update rebuild check doctor self-test stop user users remove-user build shell

deploy:
	./scripts/deploy.sh

local:
	./scripts/deploy.sh local

domain-http:
	@echo "用法: make domain-http DOMAIN=dsh.example.com [PORT=3080]"
	@test -n "$(DOMAIN)"
	./scripts/deploy.sh domain-http "$(DOMAIN)" "$(if $(PORT),$(PORT),3080)"

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

build:
	DSH_IMAGE_MODE=build ./scripts/rebuild.sh

shell:
	docker compose exec dsh bash
