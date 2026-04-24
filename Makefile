SHELL := /bin/bash

VERSION ?= 0.1.0-dev

.PHONY: help test test-package test-integration package package-test clean

help:
	@printf '%s\n' \
	  '可用目标：' \
	  '  make test                运行现有回归测试' \
	  '  make test-package        运行 prod-lite 发布包回归测试' \
	  '  make test-integration    运行可选集成测试（如无网络环境）' \
	  '  make package             构建 prod-lite 发布包，支持 VERSION=0.1.0' \
	  '  make package-test        先构建再跑发布包回归测试' \
	  '  make clean               清理 dist 目录'

test:
	bash tests/test_fscanx_pipeline.sh
	bash tests/test_fscanx_pipeline_failures.sh
	bash tests/test_prod_lite_config_uninstall.sh
	bash tests/test_prod_lite_entry_failures.sh
	bash tests/test_prod_lite_install_fallbacks.sh
	bash tests/test_build_prod_lite_failures.sh
	bash tests/run_bench_test.sh

test-package:
	bash tests/test_prod_lite_package.sh

test-integration:
	bash tests/test_no_network_integration.sh

package:
	bash scripts/build_prod_lite.sh --version "$(VERSION)"

package-test: package test-package

clean:
	rm -rf dist
