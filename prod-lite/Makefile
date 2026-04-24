SHELL := /bin/bash

SCANNER ?=
PREFIX ?=
INSTALL_DEPS ?= 0
FORCE ?= 0

INSTALL_ARGS :=

ifneq ($(strip $(SCANNER)),)
INSTALL_ARGS += --scanner $(SCANNER)
endif

ifneq ($(strip $(PREFIX)),)
INSTALL_ARGS += --prefix $(PREFIX)
endif

ifeq ($(INSTALL_DEPS),1)
INSTALL_ARGS += --install-deps
endif

ifeq ($(FORCE),1)
INSTALL_ARGS += --force
endif

.PHONY: help install install-system check print-config uninstall run start phase1 phase2

help:
	@printf '%s\n' \
	  '可用目标：' \
	  '  make install                    用户级安装，自动尝试复用系统 fscanx 或同级 fscanx-bundle' \
	  '  make install SCANNER=/path      显式指定 fscanx 路径安装' \
	  '  make install-system             系统级安装' \
	  '  make check                      执行 nmap-fscanx check' \
	  '  make print-config               打印当前生效配置' \
	  '  make run TARGETS=...            前台运行完整流程' \
	  '  make start TARGETS=...          用 tmux 后台启动' \
	  '  make uninstall                  调用卸载脚本'

install:
	bash ./install.sh $(INSTALL_ARGS)

install-system:
	bash ./install.sh --system $(INSTALL_ARGS)

check:
	@set -euo pipefail; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx check; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" check; \
	else \
	  ./bin/nmap-fscanx check; \
	fi

print-config:
	@set -euo pipefail; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx print-config; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" print-config; \
	else \
	  ./bin/nmap-fscanx print-config; \
	fi

run:
	@set -euo pipefail; \
	if [ -z "$${TARGETS:-$(TARGETS)}" ]; then \
	  echo 'TARGETS 不能为空，例如 make run TARGETS='\''192.168.1.0/24,192.168.20.0/24'\''' >&2; \
	  exit 1; \
	fi; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx run --targets "$${TARGETS:-$(TARGETS)}"; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" run --targets "$${TARGETS:-$(TARGETS)}"; \
	else \
	  ./bin/nmap-fscanx run --targets "$${TARGETS:-$(TARGETS)}"; \
	fi

start:
	@set -euo pipefail; \
	if [ -z "$${TARGETS:-$(TARGETS)}" ]; then \
	  echo 'TARGETS 不能为空，例如 make start TARGETS='\''192.168.1.0/24,192.168.20.0/24'\''' >&2; \
	  exit 1; \
	fi; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx start --targets "$${TARGETS:-$(TARGETS)}"; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" start --targets "$${TARGETS:-$(TARGETS)}"; \
	else \
	  ./bin/nmap-fscanx start --targets "$${TARGETS:-$(TARGETS)}"; \
	fi

phase1:
	@set -euo pipefail; \
	if [ -z "$${TARGETS:-$(TARGETS)}" ]; then \
	  echo 'TARGETS 不能为空，例如 make phase1 TARGETS='\''192.168.1.0/24,192.168.20.0/24'\''' >&2; \
	  exit 1; \
	fi; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx phase1 --targets "$${TARGETS:-$(TARGETS)}"; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" phase1 --targets "$${TARGETS:-$(TARGETS)}"; \
	else \
	  ./bin/nmap-fscanx phase1 --targets "$${TARGETS:-$(TARGETS)}"; \
	fi

phase2:
	@set -euo pipefail; \
	if command -v nmap-fscanx >/dev/null 2>&1; then \
	  nmap-fscanx phase2; \
	elif [ -x "$$HOME/.local/bin/nmap-fscanx" ]; then \
	  "$$HOME/.local/bin/nmap-fscanx" phase2; \
	else \
	  ./bin/nmap-fscanx phase2; \
	fi

uninstall:
	@if [ -x "$$HOME/.local/nmap-fscanx/uninstall.sh" ]; then \
	  bash "$$HOME/.local/nmap-fscanx/uninstall.sh"; \
	elif [ -x "/opt/nmap-fscanx/uninstall.sh" ]; then \
	  bash /opt/nmap-fscanx/uninstall.sh; \
	else \
	  echo '未找到已安装的卸载脚本' >&2; \
	  exit 1; \
	fi
