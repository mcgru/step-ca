.DEFAULT_GOAL := help

up: .env data   ## Запустить CA
	docker compose up -d --build

down:           ## Остановить контейнер (данные сохраняются)
	docker compose down

init: .env data nginx-config ## Инициализировать CA + сгенерировать nginx config
	docker compose build step-ca
	docker compose run --rm -T step-ca init

status:         ## Статус контейнера
	docker compose ps

logs:           ## Логи CA
	docker compose logs -f step-ca

restart:        ## Перезапустить CA без переинициализации
	docker compose restart step-ca

shell:          ## Открыть shell в контейнере step-ca
	docker compose exec --user step step-ca /bin/sh
sh:             ## Открыть shell в контейнере step-ca
	docker compose exec --user step step-ca /bin/sh

### t ?= 5m
ssh-cert: .env  ## Выпустить SSH-сертификат (make ssh-cert u=john [t=5m])
	@if [ -z "$(u)" ]; then echo "Usage: make ssh-cert u=username"; exit 1; fi
	. ./.env && \
	docker compose exec -T --user root step-ca mkdir -p /home/step/certs/ssh-user-certs && \
	docker compose exec -T --user root step-ca chown step:step /home/step/certs/ssh-user-certs && \
	docker compose exec -T --user step step-ca \
		step ssh certificate "$(u)" "/home/step/certs/ssh-user-certs/$(u).pem" \
		--provisioner "$$STEP_PROVISIONER_NAME" \
		--provisioner-password-file /home/step/secrets/provisioner-password \
		--no-password --insecure \
		--root /home/step/certs/root_ca.crt \
		--ca-url https://localhost:8443 \
		--not-after "$(or $(t),5m)" --force < /dev/null && \
	docker compose exec -T --user step step-ca \
		tar czf /home/step/certs/ssh-user-certs/$(u).tar.gz \
			-C /home/step/certs/ssh-user-certs \
			$(u).pem $(u).pem.pub $(u).pem-cert.pub && \
	docker compose exec -T --user step step-ca \
		sh -c 'echo "( base64 -d | gunzip -d | tar x ) <<<$$(base64 -w0 /home/step/certs/ssh-user-certs/$$1.tar.gz)" > "/home/step/certs/ssh-user-certs/$$1.b64"' _ "$(u)"
	@echo "Archive: data/certs/ssh-user-certs/$(u).tar.gz"
	@echo "Script:  data/certs/ssh-user-certs/$(u).b64"
	@echo ""
	@docker compose exec -T --user step step-ca cat /home/step/certs/ssh-user-certs/$(u).b64
	@echo ""
	@echo "bash $(u).b64   # on target"


ssh-host-cert: .env  ## Выпустить SSH-хостовый сертификат (make ssh-host-cert h=hostname [t=720h] [ARGS="-n alias"])
	@if [ -z "$(h)" ]; then echo "Usage: make ssh-host-cert h=hostname"; exit 1; fi
	. ./.env && \
	docker compose exec -T --user root step-ca mkdir -p /home/step/certs/ssh-host-certs && \
	docker compose exec -T --user root step-ca chown step:step /home/step/certs/ssh-host-certs && \
	docker compose exec -T --user step step-ca \
		step ssh certificate "$(h)" "/home/step/certs/ssh-host-certs/$(h).pem" \
		--host \
		--provisioner "$$STEP_PROVISIONER_NAME" \
		--provisioner-password-file /home/step/secrets/provisioner-password \
		--no-password --insecure \
		--root /home/step/certs/root_ca.crt \
		--ca-url https://localhost:8443 \
		--not-after "$(or $(t),720h)" $(ARGS) --force < /dev/null && \
	docker compose exec -T --user step step-ca \
		tar czf /home/step/certs/ssh-host-certs/$(h).tar.gz \
			-C /home/step/certs/ssh-host-certs \
			$(h).pem $(h).pem.pub $(h).pem-cert.pub && \
	docker compose exec -T --user step step-ca \
		sh -c 'echo "( base64 -d | gunzip -d | tar x ) <<<$$(base64 -w0 /home/step/certs/ssh-host-certs/$$1.tar.gz)" > "/home/step/certs/ssh-host-certs/$$1.b64"' _ "$(h)"
	@echo "Archive: data/certs/ssh-host-certs/$(h).tar.gz"
	@echo "Script:  data/certs/ssh-host-certs/$(h).b64"
	@echo ""
	@docker compose exec -T --user step step-ca cat /home/step/certs/ssh-host-certs/$(h).b64
	@echo ""
	@echo "bash $(h).b64   # on target"

provisioner-add: .env ## Добавить провизер (make provisioner-add NAME=admin2 TYPE=JWK)
	@if [ -z "$(NAME)" ]; then echo "Usage: make provisioner-add NAME=name TYPE=JWK|ACME|OIDC [ARGS=...]"; exit 1; fi
#	@if [ -s ./.env ]; then source ./.env ; fi
	docker compose exec -T --user step step-ca \
		step ca provisioner add "$(NAME)" --type "$(TYPE)" $(ARGS)
#		--admin-name "$$STEP_PROVISIONER_NAME" \
#		--admin-password-file /home/step/secrets/provisioner-password
	@echo "==> Provisioner '$(NAME)' added. Run 'make restart' to apply."

provisioner-list: ## Список провизеров
#	@if [ -s ./.env ]; then source ./.env ; fi
	docker compose exec -T --user step step-ca \
		step ca provisioner list
#		--admin-name "$$STEP_PROVISIONER_NAME" \
#		--admin-password-file /home/step/secrets/provisioner-password

provisioner-remove: .env ## Удалить провизер (make provisioner-remove NAME=admin2)
#	@if [ -s ./.env ]; then source ./.env ; fi
	@if [ -z "$(NAME)" ]; then echo "Usage: make provisioner-remove NAME=name"; exit 1; fi
	docker compose exec -T --user step step-ca \
		step ca provisioner remove "$(NAME)"
#		--admin-name "$$STEP_PROVISIONER_NAME" \
#		--admin-password-file /home/step/secrets/provisioner-password
	@echo "==> Provisioner '$(NAME)' removed. Run 'make restart' to apply."

ca-cert:        ## Скопировать корневой сертификат CA в data/
	docker compose cp step-ca:/home/step/certs/root_ca.crt data/
	@echo "Saved to data/root_ca.crt"

reset:          ## [ОСТОРОЖНО] Удалить ВСЕ данные CA
	@echo "Удалить data/ и nginx-config/? [y/N]"; \
	read ans; \
	if [ "$$ans" = "y" ]; then \
		docker compose down -v; \
		rm -rf data nginx-config; \
		echo "Готово. Запустите 'make up' для чистой установки."; \
	fi

help:           ## Показать эту справку
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

data:
	mkdir -p data

nginx-config:
	mkdir -p nginx-config

.env:
	cp .env.example .env
	@echo "==> Создан .env из .env.example. Отредактируйте его и запустите 'make up'."
