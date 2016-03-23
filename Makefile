
# settings

pg_user = postgres

db_user = yunity-user
db_name = yunity-database
db_test_name = test_yunity-database
db_password = yunity

swagger_version = 2.1.3

# $(1) will be replaced with a postgres tool (psql|createuser|createdb)
# you can override this in local_settings.make so make it use "sudo -u ", etc....

pg = $(1) -U $(pg_user)

PSQL = $(call pg,psql)
CREATEDB = $(call pg,createdb)
CREATEUSER = $(call pg,createuser)
DROPDB= $(call pg,dropdb)
DROPUSER= $(call pg,dropuser)

git_url_base = https://github.com/yunity/

# override settings, optionally

-include local_settings.make

# commands we can run a check for

deps := wget git postgres redis-server virtualenv node npm

# all yunity-* projects

frontend_project_dirs = yunity-webapp-common yunity-webapp-mobile
backend_project_dirs = yunity-core yunity-sockets
project_dirs = $(frontend_project_dirs) $(backend_project_dirs)

.PHONY: setup update setup-core setup-sockets setup-webapp-common setup-webapp setup-webapp-mobile git-pull-frontend git-pull-backend pip-install migrate-db init-db check-deps $(deps)

# setup
#
# ensures all the source code for the projects is available
#  (will check it out if not)
# ensures database and users are created
# runs all the npm/bower/pip/django/migation steps
setup: setup-backend setup-frontend

setup-backend: setup-core setup-sockets setup-swagger-ui
setup-frontend: setup-webapp-common setup-webapp-mobile


$(deps):
	@(which $@ >/dev/null 2>&1 && echo -e "$@ \xE2\x9C\x93") || echo -e "$@ \xE2\x9C\x95"

check-deps: $(deps)

# update
#
# updates self this repo
# then reruns make to do the actual setup
#
update:
	@echo && echo "# $@" && echo
	@git pull
	@make git-pull-backend git-pull-frontend setup

# update-backend
#
# just update backend stuff so don't have to wait for npm...
update-backend:
	@echo && echo "# $@" && echo
	@git pull
	@make git-pull-backend setup-backend

update-frontend:
	@echo && echo "# $@" && echo
	@git pull
	@make git-pull-frontend setup-frontend

setup-core: | yunity-core init-db pip-install migrate-db

setup-sockets: | yunity-sockets npm-system-deps
	@echo && echo "# $@" && echo
	@cd yunity-sockets && npm-cache install npm --unsafe-perm

setup-webapp-common: | yunity-webapp-common npm-deps npm-system-deps
	@echo && echo "# $@" && echo
	@cd yunity-webapp-common && npm-cache install npm

setup-webapp: | yunity-webapp-common yunity-webapp npm-deps npm-system-deps
	@echo && echo "# $@" && echo
	@cd yunity-webapp && npm-cache install npm --unsafe-perm
	@cd yunity-webapp && npm-cache install bower --allow-root
	@rm -rf yunity-webapp/node_modules/yunity-webapp-common
	@cd yunity-webapp/node_modules && ln -s ../../yunity-webapp-common .
	#@cd yunity-webapp && $$(npm bin)/webpack

build-webapp:
	@cd yunity-webapp && $$(npm bin)/webpack

setup-webapp-mobile: | yunity-webapp-common yunity-webapp-mobile npm-deps npm-system-deps
	@echo && echo "# $@" && echo
	@cd yunity-webapp-mobile && npm-cache install npm --unsafe-perm
	@cd yunity-webapp-mobile && npm-cache install bower --allow-root
	@rm -rf yunity-webapp-mobile/node_modules/yunity-webapp-common
	@cd yunity-webapp-mobile/node_modules && ln -s ../../yunity-webapp-common .

build-webapp-mobile:
	@cd yunity-webapp-mobile && $$(npm bin)/webpack

# setup-swagger-ui
#
# delete existing one, and put a new one in
# we use a custom swagger html page which
#   1. prepopulates the url inside the page with the correct one
#   2. adds django csrf headers to xhr requests
setup-swagger-ui: | clean-swagger-ui swagger-ui
	@cp index-yunity.html swagger-ui/swagger/dist/

clean-swagger-ui:
	@rm -rf swagger-ui

swagger-$(swagger_version).tar.gz:
	@wget https://github.com/swagger-api/swagger-ui/archive/v$(swagger_version).tar.gz -O swagger-$(swagger_version).tar.gz

swagger-ui: swagger-$(swagger_version).tar.gz
	@tar zxvf swagger-$(swagger_version).tar.gz
	@mkdir -p swagger-ui
	@mv swagger-ui-$(swagger_version) swagger-ui/swagger
	@cd swagger-ui/swagger/dist && patch -p0 < ../../../swagger-ui.patch



# ensure each project folder is available or check it out if not
$(project_dirs):
	@echo && echo "# $@" && echo
	@git clone $(git_url_base)$@.git

git-pull-frontend:
	@echo && echo "# $@" && echo
	@for dir in $(frontend_project_dirs); do \
		echo "git pulling $$dir"; \
		cd $$dir && git pull --rebase; cd -; \
  done;

git-pull-backend:
	@echo && echo "# $@" && echo
	@for dir in $(backend_project_dirs); do \
		echo "git pulling $$dir"; \
		cd $$dir && git pull --rebase; cd -; \
  done;

# init-db
#
# create database and user if they don't exist
init-db:
	@echo && echo "# $@" && echo
	@$(PSQL) postgres -tAc \
		"SELECT 1 FROM pg_roles WHERE rolname='$(db_user)'" | grep -q 1 || \
		$(PSQL) -tAc "create user \"$(db_user)\" with CREATEDB password '$(db_password)'"  || \
		echo "--> failed to create db user $(db_user), please set pg_user or pg in local_settings.make or ensure the default 'postgres' db role is available"
	@$(PSQL) postgres -tAc \
		"SELECT 1 FROM pg_database WHERE datname = '$(db_name)'" | grep -q 1 || \
		$(CREATEDB) $(db_name) || \
		echo "--> failed to create db user $(db_user), please set pg_user or pg in local_settings.make or ensure the default 'postgres' db role is available"

# drop-db
#
# drop db and user if they exist
drop-db:
	@echo && echo "# $@" && echo
	@$(DROPDB) $(db_name) --if-exists
	@$(DROPDB) $(db_test_name) --if-exists
	@$(DROPUSER) $(db_user) --if-exists

disconnect-db-sessions:
	@$(PSQL) postgres -tAc \
		"SELECT pg_terminate_backend(pid) FROM pg_stat_activity where datname IN ('${db_name}', '${db_test_name}');"

# recreate-db
#
# drop, then create
recreate-db: | disconnect-db-sessions drop-db init-db
	@echo && echo "# $@" && echo

yunity-core/base/migrations:
	@echo && echo "# $@" && echo
	@cd yunity-core && env/bin/python manage.py makeallmigrations 

# migate-db
#
# run django migrations
migrate-db: yunity-core/env yunity-core/config/local_settings.py init-db yunity-core/base/migrations
	@echo && echo "# $@" && echo
	@cd yunity-core && env/bin/python manage.py migrate

# copy default dev local_settings.py with db details for django
yunity-core/config/local_settings.py:
	@echo && echo "# $@" && echo
	@cp local_settings.py.dev-default yunity-core/config/local_settings.py

# pip install env
pip-install: yunity-core/env
	@echo && echo "# $@" && echo
	@cd yunity-core && env/bin/pip install -r requirements.txt

# virtualenv initialization
yunity-core/env:
	@echo && echo "# $@" && echo
	@virtualenv --python=python3 --no-site-packages yunity-core/env

# system-wide npm deps (TODO(ns) make nothing depend on global npm modules)
npm-system-deps:
	@echo && echo "# $@" && echo
	@which npm-cache || sudo npm install -g npm-cache
	@which bower || sudo npm install -g bower
	@which pm2 || sudo npm install -g pm2

# npm-deps
#
# install some npm stuff for the yunity-setup project
# mostly stuff for proxy.js...
npm-deps:
	@echo && echo "# $@" && echo
	@npm-cache install npm --unsafe-perm
