# F1 Prediction Game — common dev tasks
#
# Usage examples:
#   make up                   # start the local backend (db + dev server)
#   make app                  # run the iOS app against the local backend
#   make app-mock             # run the iOS app against fixtures
#   make bootstrap            # populate the backend's schedule from Jolpica
#   make crawl                # force a crawler tick to fetch finished results
#   make test                 # run all backend + frontend tests
#
# Override DEVICE on the command line if you want a different Flutter target:
#   make app DEVICE=chrome
#   make app DEVICE=macos

SHELL := /bin/zsh

# ---- config ----------------------------------------------------------------

# iPhone 17 Pro simulator (override with: make app DEVICE=chrome)
DEVICE      ?= 76ADD67A-99F4-4B62-A103-D4B51A0F0C82
API_URL     ?= http://localhost:3000
ADMIN_TOKEN ?= local-dev-token
BACKEND     := backend

# ---- meta ------------------------------------------------------------------

.PHONY: help
help:           ## show this list
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]+:.*?##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ---- database --------------------------------------------------------------

.PHONY: db-up
db-up:          ## start the local postgres container
	cd $(BACKEND) && docker compose up -d db

.PHONY: db-down
db-down:        ## stop the postgres container
	cd $(BACKEND) && docker compose down

.PHONY: db-reset
db-reset:       ## destroy and recreate the postgres volume
	cd $(BACKEND) && docker compose down -v && docker compose up -d db

.PHONY: db-shell
db-shell:       ## psql into the local db
	docker exec -it -e PGPASSWORD=f1pg_dev backend-db-1 psql -U f1pg -d f1pg

# ---- backend ---------------------------------------------------------------

.PHONY: backend-install
backend-install:  ## install backend node deps
	cd $(BACKEND) && npm install

.PHONY: migrate
migrate:        ## run backend db migrations
	cd $(BACKEND) && set -a && source .env && set +a && npm run db:migrate

.PHONY: backend
backend:        ## run the backend dev server (tsx watch)
	cd $(BACKEND) && set -a && source .env && set +a && npm run dev

.PHONY: backend-test
backend-test:   ## run backend vitest suite
	cd $(BACKEND) && set -a && source .env && set +a && npm test

.PHONY: bootstrap
bootstrap:      ## POST /admin/bootstrap (populate schedule from Jolpica)
	@curl -fsS -X POST -H "X-Admin-Token: $(ADMIN_TOKEN)" $(API_URL)/admin/bootstrap | python3 -m json.tool

.PHONY: crawl
crawl:          ## POST /admin/crawl (force a crawler tick)
	@curl -fsS -X POST -H "X-Admin-Token: $(ADMIN_TOKEN)" $(API_URL)/admin/crawl | python3 -m json.tool

.PHONY: refresh-openf1
refresh-openf1:  ## POST /admin/refresh-openf1-metadata (token-gated)
	@curl -fsS -X POST -H "X-Admin-Token: $(ADMIN_TOKEN)" $(API_URL)/admin/refresh-openf1-metadata | python3 -m json.tool

.PHONY: health
health:         ## GET /api/health
	@curl -fsS $(API_URL)/api/health | python3 -m json.tool

# ---- frontend --------------------------------------------------------------

.PHONY: frontend-install
frontend-install: ## install flutter packages
	flutter pub get

.PHONY: test
test:           ## run flutter + backend tests
	flutter test
	$(MAKE) backend-test

.PHONY: analyze
analyze:        ## flutter analyze
	flutter analyze

.PHONY: app
app:            ## run the flutter app against the backend at $(API_URL)
	flutter run -d "$(DEVICE)" --dart-define=API_URL=$(API_URL)

# ---- combined --------------------------------------------------------------

.PHONY: up
up: db-up       ## bring db up and start the backend dev server
	@echo "Waiting for postgres to be ready..."
	@until docker exec backend-db-1 pg_isready -U f1pg -d f1pg > /dev/null 2>&1; do sleep 0.5; done
	@$(MAKE) backend

.PHONY: seed
seed: bootstrap crawl  ## bootstrap then crawl to populate events + results

.PHONY: install
install: frontend-install backend-install  ## install all deps

.PHONY: clean
clean:          ## stop backend container and tear down the db volume
	$(MAKE) db-down
