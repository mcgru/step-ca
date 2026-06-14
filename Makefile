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

ssh-cert: .env  ## Выпустить SSH-сертификат (make ssh-cert USER=john)
	@if [ -z "$(USER)" ]; then echo "Usage: make ssh-cert USER=username"; exit 1; fi
	mkdir -p data/certs
	docker compose exec --user step step-ca \
		step ssh certificate "$(USER)" "/home/step/certs/$(USER).pem" \
		--provisioner "$(STEP_PROVISIONER_NAME)" \
		--provisioner-password-file /home/step/secrets/provisioner-password
	@echo "Cert saved to data/certs/$(USER).pem"

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
