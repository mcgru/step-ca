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
		sh -c 'printf "%s\n" \
			"# SSH User Certificate for $$1" \
			"" \
			"## Files" \
			"$$1.pem              - Private key (unencrypted)" \
			"$$1.pem.pub          - Public key" \
			"$$1.pem-cert.pub     - SSH certificate" \
			"ssh_host_ca_key.pub  - Host CA public key (for known_hosts)" \
			"README.md            - This file" \
			"" \
			"## Setup on client machine" \
			"" \
			"  1. Copy to ~/.ssh/:" \
			"     cp $$1.pem ~/.ssh/id_ecdsa" \
			"     chmod 600 ~/.ssh/id_ecdsa" \
			"     cp $$1.pem-cert.pub ~/.ssh/id_ecdsa-cert.pub" \
			"" \
			"  2. Add host CA to known_hosts:" \
			"     cat ssh_host_ca_key.pub | sed '\''s/^/@cert-authority */'\'' >> ~/.ssh/known_hosts" \
			"" \
			"  3. Connect:" \
			"     ssh -i ~/.ssh/id_ecdsa $$1@host" \
		> /tmp/README.md' _ "$(u)" && \
	docker compose exec -T --user root step-ca sh -c '\
		rm -rf /tmp/cert-pack && mkdir -p /tmp/cert-pack && \
		cp /home/step/certs/ssh-user-certs/$$1.pem /tmp/cert-pack/ && \
		cp /home/step/certs/ssh-user-certs/$$1.pem.pub /tmp/cert-pack/ && \
		cp /home/step/certs/ssh-user-certs/$$1.pem-cert.pub /tmp/cert-pack/ && \
		cp /home/step/certs/ssh_host_ca_key.pub /tmp/cert-pack/ && \
		cp /tmp/README.md /tmp/cert-pack/ && \
		chown -R step:step /tmp/cert-pack' _ "$(u)" && \
	docker compose exec -T --user step step-ca \
		tar czf /home/step/certs/ssh-user-certs/$(u).tar.gz -C /tmp/cert-pack . && \
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
		sh -c 'printf "%s\n" \
			"# SSH Host Certificate for $$1" \
			"" \
			"## Files" \
			"$$1.pem               - Host private key" \
			"$$1.pem.pub           - Host public key" \
			"$$1.pem-cert.pub      - Host certificate" \
			"ssh_user_ca_key.pub   - User CA public key (for sshd_config)" \
			"README.md             - This file" \
			"" \
			"## Setup on target server" \
			"" \
			"  1. Install host key and certificate:" \
			"     sudo cp $$1.pem /etc/ssh/ssh_host_ecdsa_key" \
			"     sudo chmod 600 /etc/ssh/ssh_host_ecdsa_key" \
			"     sudo cp $$1.pem-cert.pub /etc/ssh/ssh_host_ecdsa_key-cert.pub" \
			"" \
			"  2. Configure user CA:" \
			"     sudo cp ssh_user_ca_key.pub /etc/ssh/" \
			"     echo '\''TrustedUserCAKeys /etc/ssh/ssh_user_ca_key.pub'\'' | sudo tee -a /etc/ssh/sshd_config" \
			"" \
			"  3. Restart sshd:" \
			"     sudo systemctl restart sshd" \
		> /tmp/README.md' _ "$(h)" && \
	docker compose exec -T --user root step-ca sh -c '\
		rm -rf /tmp/cert-pack && mkdir -p /tmp/cert-pack && \
		cp /home/step/certs/ssh-host-certs/$$1.pem /tmp/cert-pack/ && \
		cp /home/step/certs/ssh-host-certs/$$1.pem.pub /tmp/cert-pack/ && \
		cp /home/step/certs/ssh-host-certs/$$1.pem-cert.pub /tmp/cert-pack/ && \
		cp /home/step/certs/ssh_user_ca_key.pub /tmp/cert-pack/ && \
		cp /tmp/README.md /tmp/cert-pack/ && \
		chown -R step:step /tmp/cert-pack' _ "$(h)" && \
	docker compose exec -T --user step step-ca \
		tar czf /home/step/certs/ssh-host-certs/$(h).tar.gz -C /tmp/cert-pack . && \
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
