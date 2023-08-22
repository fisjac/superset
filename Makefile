#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Python version installed; we need 3.9-3.11
PYTHON=`command -v python3.11 || command -v python3.10 || command -v python3.9`

.PHONY: install superset venv pre-commit

install: superset pre-commit

superset:
	# Install external dependencies
	pip install -r requirements/local.txt

	# Install Superset in editable (development) mode
	pip install -e .

	# Create an admin user in your metadata database
	superset fab create-admin \
                    --username admin \
                    --firstname "Admin I."\
                    --lastname Strator \
                    --email admin@superset.io \
                    --password general

	# Initialize the database
	superset db upgrade

	# Create default roles and permissions
	superset init

	# Load some data to play with
	superset load-examples

	# Install node packages
	cd superset-frontend; npm ci

update: update-py update-js

update-py:
	# Install external dependencies
	pip install -r requirements/local.txt

	# Install Superset in editable (development) mode
	pip install -e .

	# Initialize the database
	superset db upgrade

	# Create default roles and permissions
	superset init

update-js:
	# Install js packages
	cd superset-frontend; npm ci

venv:
	# Create a virtual environment and activate it (recommended)
	if ! [ -x "${PYTHON}" ]; then echo "You need Python 3.9, 3.10 or 3.11 installed"; exit 1; fi
	test -d venv || ${PYTHON} -m venv venv # setup a python3 virtualenv
	. venv/bin/activate

activate:
	. venv/bin/activate

pre-commit:
	# setup pre commit dependencies
	pip3 install -r requirements/integration.txt
	pre-commit install

format: py-format js-format

py-format: pre-commit
	pre-commit run black --all-files

py-lint: pre-commit
	pylint -j 0 superset

js-format:
	cd superset-frontend; npm run prettier

flask-app: activate
	flask run -p 8088 --with-threads --reload --debugger

node-app:
	cd superset-frontend; npm run dev-server

build-cypress:
	cd superset-frontend; npm run build-instrumented
	cd superset-frontend/cypress-base; npm ci

open-cypress:
	if ! [ $(port) ]; then cd superset-frontend/cypress-base; CYPRESS_BASE_URL=http://localhost:9000 npm run cypress open; fi
	cd superset-frontend/cypress-base; CYPRESS_BASE_URL=http://localhost:$(port) npm run cypress open

report-celery-worker:
	celery --app=superset.tasks.celery_app:app worker

report-celery-beat:
	celery --app=superset.tasks.celery_app:app beat --pidfile /tmp/celerybeat.pid --schedule /tmp/celerybeat-schedulecd

admin-user:
	superset fab create-admin

# Create a postgres instance using docker
# CLI: $ psql postgresql://postgres:1234@localhost:5432/postgres
# superset_config.py: SQLALCHEMY_DATABASE_URI = 'postgresql://postgres:1234@localhost:5432/postgres'
db:
	# start postgres with detached mode
	docker run -d -p 127.0.0.1:5432:5432 -e POSTGRES_PASSWORD="1234" --name pg postgres:alpine;\
	EXIT_CODE=$$?;\
	echo $$EXIT_CODE;\
	echo "command exited with $$EXIT_CODE";\
	if [ $$EXIT_CODE -ne "0" ]; then docker start pg; echo "DB has been created"; fi

db-stop:
	docker stop pg

cache:
	docker run -d --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest;\
	EXIT_CODE=$$?;\
	echo $$EXIT_CODE;\
	echo "command exited with $$EXIT_CODE";\
	if [ $$EXIT_CODE -ne "0" ]; then docker start redis-stack-server; echo "cache has been created"; fi

cache-stop:
	docker stop redis-stack-server

# Primarily made for GH codespaces but this flow could work on your local as well
api: db flask-app
client: node-app