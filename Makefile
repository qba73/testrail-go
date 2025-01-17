.PHONY: help check cover test tidy

ROOT			:= $(PWD)
GO_HTML_COV 		:= ./coverage.html
GO_TEST_OUTFILE 	:= ./c.out
GO_DOCKER_IMAGE 	:= golang:1.16
GO_DOCKER_CONTAINER := rivers-container
CC_TEST_REPORTER_ID := ${CC_TEST_REPORTER_ID}
CC_PREFIX := github.com/qba73/testrail


define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
	match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
	if match:
		target, help = match.groups()
		print("%-20s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT

default: test

help:
	@python -c "$$PRINT_HELP_PYSCRIPT" < $(MAKEFILE_LIST)

check: ## Run static check analyzer
	staticcheck ./...

cover: ## Run unit tests and generate test coverage report
	go test -v ./... -count=1 -covermode=count -coverprofile=coverage.out
	go tool cover -html coverage.out
	staticcheck ./...

test: ## Run unit tests locally
	go test -v -count=1

# MODULES
tidy: ## Run go mod tidy and vendor
	go mod tidy
	go mod vendor


clean: ## Remove docker container if exist
	docker rm -f ${GO_DOCKER_CONTAINER} || true

testdocker: ## Run unittests inside a container
	docker run -w /app -v ${ROOT}:/app ${GO_DOCKER_IMAGE} go test ./... -coverprofile=${GO_TEST_OUTFILE}
	docker run -w /app -v ${ROOT}:/app ${GO_DOCKER_IMAGE} go tool cover -html=${GO_TEST_OUTFILE} -o ${GO_HTML_COV}

lint: ## Run linter inside container
	docker run --rm -v ${ROOT}:/data cytopia/golint .

# Custom logic for code climate
_before-cc:
	# Download CC test reported
	docker run -w /app -v ${ROOT}:/app ${GO_DOCKER_IMAGE} \
		/bin/bash -c \
		"curl -L https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64 > ./cc-test-reporter"
	
	# Make reporter executable
	docker run -w /app -v ${ROOT}:/app ${GO_DOCKER_IMAGE} chmod +x ./cc-test-reporter

	# Run before build
	docker run -w /app -v ${ROOT}:/app \
		-e CC_TEST_REPORTER_ID=${CC_TEST_REPORTER_ID} ${GO_DOCKER_IMAGE} \
		./cc-test-reporter before-build

_after-cc:
	# Handle custom prefix
	$(eval PREFIX=${CC_PREFIX})
ifdef prefix
	$(eval PREFIX=${prefix})
endif
	# Upload data to CC
	docker run -w /app -v ${ROOT}:/app \
		-e CC_TEST_REPORTER_ID=${CC_TEST_REPORTER_ID} \
		${GO_DOCKER_IMAGE} ./cc-test-reporter after-build --prefix ${PREFIX}

test-ci: _before-cc testdocker _after-cc
