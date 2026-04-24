# 运维转发说明

把压缩包发给同事后，直接转下面这段：

这是 `nmap-fscanx` 的内部发布包。安装后先跑第一阶段，看结果，再决定要不要跑第二阶段。

```bash
tar -xzf nmap-fscanx-0.1.0.tar.gz
cd nmap-fscanx-0.1.0
make install
nmap-fscanx check

nmap-fscanx phase1 --targets '192.168.1.0/24,192.168.20.0/24' --scan-root './scans/onsite-20260424'
cat ./scans/onsite-20260424/phase1/alive_ips.txt

nmap-fscanx phase2 --scan-root './scans/onsite-20260424'
```

注意：

- `phase2` 要和 `phase1` 用同一个 `--scan-root`
- 结果主要看 `phase1/alive_ips.txt`、`phase2/open_ip_port.txt`、`report.json`
- 如果 `nmap-fscanx check` 里有 `SCANNER_STATUS=missing`、`JQ_STATUS=missing` 或 `TMUX_STATUS=missing`，先补依赖再执行

如果不想分两步看，也可以直接后台跑完整流程：

```bash
nmap-fscanx start --targets '192.168.1.0/24,192.168.20.0/24'
```

进入后台会话：

```bash
nmap-fscanx attach --session nmap-fscanx-scan-20260424
```

详细说明看：

- `docs/INSTALL.md`
- `docs/QUICKSTART.md`
- `docs/OUTPUTS.md`
