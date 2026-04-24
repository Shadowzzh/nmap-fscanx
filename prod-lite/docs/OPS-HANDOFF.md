# 运维转发说明

把压缩包发给同事后，直接转下面这段即可。

## 转发模板

这是 `nmap-fscanx` 的内部发布包，用来跑 `fscanx` 两阶段扫描。

使用步骤：

```bash
tar -xzf nmap-fscanx-0.1.0.tar.gz
cd nmap-fscanx-0.1.0
make install
nmap-fscanx check
nmap-fscanx start --targets '192.168.1.0/24,192.168.20.0/24'
```

发布包默认自带 `fscanx-bundle/`，所以正常情况下不需要额外再放一份。

如果你手工删掉了包内 bundle，或者想覆盖默认 bundle，才需要在发布包同级再放：

```text
./fscanx-bundle
```

如果自动识别失败，再改成：

```bash
make install SCANNER=/path/to/fscanx
```

进入后台会话：

```bash
nmap-fscanx attach --session nmap-fscanx-scan-20260424
```

重点结果文件：

- `phase1/alive_ips.txt`
- `phase2/open_ip_port.txt`
- `report.json`

如果 `nmap-fscanx check` 里看到：

- `SCANNER_STATUS=missing`
- `JQ_STATUS=missing`
- `TMUX_STATUS=missing`

先补对应依赖，再执行扫描。

详细文档：

- `README.md`
- `docs/INSTALL.md`
- `docs/QUICKSTART.md`
- `docs/OUTPUTS.md`
