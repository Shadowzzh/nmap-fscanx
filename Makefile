SHELL := /bin/bash

VERSION ?= 0.1.0-dev

.PHONY: help test test-package package package-test clean

help:
	@printf '%s\n' \
	  '可用目标：' \
	  '  make test                运行现有回归测试' \
	  '  make test-package        运行 prod-lite 发布包回归测试' \
	  '  make package             构建 prod-lite 发布包，支持 VERSION=0.1.0' \
	  '  make package-test        先构建再跑发布包回归测试' \
	  '  make clean               清理 dist 目录'

test:
	bash tests/test_fscanx_pipeline.sh
	bash tests/run_bench_test.sh

test-package:
	bash tests/test_prod_lite_package.sh

package:
	bash scripts/build_prod_lite.sh --version "$(VERSION)"

package-test: package test-package

clean:
	rm -rf dist
