.DEFAULT_GOAL := help

up: .env   ## Запустить CA + PostgreSQL
	docker compose up -d --build

down:      ## Остановить контейнеры (данные сохраняются)
	docker compose down

init: .env ## Инициализировать CA вручную
	docker compose run --rm step-ca init

status:    ## Статус контейнеров
	docker compose ps

logs:      ## Логи CA
	docker compose logs -f step-ca

restart:   ## Перезапустить CA без переинициализации
	docker compose restart step-ca

shell:     ## Открыть shell в контейнере step-ca
	docker compose exec step-ca /bin/sh

ssh-cert: .env ## Выпустить SSH-сертификат (make ssh-cert USER=john)
	@if [ -z "$(USER)" ]; then echo "Usage: make ssh-cert USER=username"; exit 1; fi
	mkdir -p certs
	docker compose run --rm -v "$$(pwd)/certs:/home/step/certs" step-ca \
		step ssh certificate "$(USER)" "/home/step/certs/$(USER).pem" \
		--provisioner "$(STEP_PROVISIONER_NAME)" \
		--provisioner-password-file /home/step/secrets/provisioner-password
	@echo "Cert saved to certs/$(USER).pem"

reset:     ## [ОСТОРОЖНО] Удалить ВСЕ данные CA и БД
	@echo "Удалить все volumes (CA и PostgreSQL)? [y/N]"; \
	read ans; \
	if [ "$$ans" = "y" ]; then \
		docker compose down -v; \
		echo "Готово. Запустите 'make up' для чистой установки."; \
	fi

help:      ## Показать эту справку
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.env:
	cp .env.example .env
	@echo "==> Создан .env из .env.example. Отредактируйте его и запустите 'make up'."
