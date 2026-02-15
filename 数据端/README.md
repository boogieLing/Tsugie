# 数据端

本目录用于活动数据处理、接口设计与推荐排序实现。

## 统一管理系统（HANABI + OMATSURI）

一键启动：

```bash
./scripts/start_ops_console.sh
```

地址：`http://127.0.0.1:8788`

运维命令：

```bash
./scripts/ops_console.sh status
./scripts/ops_console.sh logs
./scripts/ops_console.sh stop
./scripts/ops_console.sh restart
```

说明：
- 首次运行会自动检查/创建 conda 环境 `hanabi-ops`（基于 `HANABI/environment.yml`）。
- 可通过环境变量覆盖：`HANABI_CONDA_ENV`、`HANABI_OPS_HOST`、`HANABI_OPS_PORT`。
