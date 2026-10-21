# luyin 知识引擎 K8s 部署（fork 定制区）

> 目标：把 WeKnora fork（`queankeji/WeKnora`，基线 `e28c68cf5` / v0.8.3）部署到
> `knowledge-engine` namespace，作为 luyin 知识平台**内部引擎运行时**——
> 不对租户直接暴露，唯一可信调用方是 `luyin-main` namespace 里的 luyin api-server（BFF）。
>
> 本目录全部为**新增文件**（不改上游 `helm/`、`docker-compose.yml`），上游 rebase 零冲突。

## 文件清单

| 文件 | 用途 |
|---|---|
| `values-luyin.yaml` | 上游 helm chart 的覆盖值：镜像锁定 v0.8.3、资源 request/limit、PVC 容量、关闭 Ingress 与可选组件 |
| `networkpolicy.yaml` | 默认拒绝全部入站；仅放行 luyin-main→app:8080、引擎内部互访、monitoring 探测 |
| `README.md` | 本文档 |

## 部署步骤

### 1. 前置确认

- 集群 CNI 支持 NetworkPolicy（Calico / Cilium；flannel 不生效——网络收口会失效，禁止在此类集群上对公网暴露）
- 已创建（或有权创建）namespace `knowledge-engine`
- 节点资源余量 ≥ 4C / 8Gi（见下方资源配额建议）

### 2. 创建外部 Secret（密钥不进 values 文件、不进 Git）

```bash
kubectl -n knowledge-engine create secret generic weknora-secrets \
  --from-literal=DB_USER=postgres \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=DB_NAME=weknora \
  --from-literal=REDIS_USERNAME="" \
  --from-literal=REDIS_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=JWT_SECRET="$(openssl rand -hex 32)" \
  --from-literal=SYSTEM_AES_KEY="$(openssl rand -hex 16)"
```

> ⚠️ `SYSTEM_AES_KEY` 必须为**恰好 32 字节**的字符串：`openssl rand -hex 16` 生成 32 个
> 十六进制字符（32 字节），满足要求；`openssl rand -hex 32` 是 64 字符，**不**满足。
> 丢失该 Key 则已加密字段（租户 API Key、模型 Key 等）全部不可恢复——请同时备份到密钥管理系统。

### 3. Helm 安装 / 升级

```bash
cd <fork 仓库根目录>

# 首次安装
helm upgrade --install weknora ./helm \
  -n knowledge-engine --create-namespace \
  -f deploy-luyin/values-luyin.yaml

# 后续升级（版本变更只能跟随 fork rebase 节奏，改 values-luyin.yaml 的 image.tag）
helm upgrade weknora ./helm \
  -n knowledge-engine \
  -f deploy-luyin/values-luyin.yaml
```

### 4. 网络收口

```bash
kubectl apply -f deploy-luyin/networkpolicy.yaml
```

> 注意：`networkpolicy.yaml` 中 Pod 标签与 helm release 名 `weknora` 绑定
> （`app.kubernetes.io/instance: weknora`）。若换 release 名，需同步修改标签。

### 5. 验证

```bash
# Pod 全部 Running/Ready
kubectl -n knowledge-engine get pods -w

# app 健康（BFF 视角的调用路径）
kubectl -n luyin-main run curl-test --rm -it --image=curlimages/curl -- \
  curl -fsS http://weknora-app.knowledge-engine.svc.cluster.local:8080/health

# 负向：其他 namespace 访问应超时（网络策略生效证明）
kubectl -n default run curl-neg --rm -it --image=curlimages/curl -- \
  curl -m 3 -sS http://weknora-app.knowledge-engine.svc.cluster.local:8080/health || echo "BLOCKED (expected)"
```

Service 名称：release 名为 `weknora` 时，app Service 为 `weknora-app`（ClusterIP，port 8080）。
BFF 侧配置的服务间地址即 `http://weknora-app.knowledge-engine.svc.cluster.local:8080`。

## Prometheus 抓取接入（与主系统同一 Grafana）

现状（v0.8.3）：**WeKnora app 无原生 `/metrics` 端点**（上游可观测走 Langfuse，
见 `.env` 的 LANGFUSE_* 段与 `website-docs/03-features/16-observability.md`）。
因此 K8s 层接入分三块：

### a) 存活与延迟：黑盒探测 /health（推荐，零侵入）

```yaml
# prometheus blackbox-exporter 的 additional target（或入主系统 Prometheus 配置）
- job_name: weknora-health
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
        - http://weknora-app.knowledge-engine.svc.cluster.local:8080/health
  relabel_configs:
    - { source_labels: [__address__], target_label: __param_target }
    - { source_labels: [__param_target], target_label: instance }
    - { target_label: __address__, replacement: prometheus-blackbox-exporter.monitoring:9115 }
```

若集群用 ServiceMonitor（Prometheus Operator），等价写法：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: weknora-health
  namespace: knowledge-engine
  labels: { release: prometheus }   # 按主系统 Prometheus 的 selector 实际值改
spec:
  jobName: weknora-health
  prober:
    url: prometheus-blackbox-exporter.monitoring:9115
  targets:
    staticConfig:
      static:
        - http://weknora-app.knowledge-engine.svc.cluster.local:8080/health
```

### b) 容器/编排层指标（无需改动）

Prometheus 已有的 kube-state-metrics + cadvisor/kubelet 指标自动覆盖
knowledge-engine namespace 的 Pod 重启、OOM、CPU/内存水位（配合上面 values-luyin.yaml 的 request/limit）。

### c) 中间件指标（可选）

- PostgreSQL：部署 `prometheuscommunity/postgres-exporter`，DATA_SOURCE_NAME 指向
  `weknora-postgres.knowledge-engine.svc:5432/weknora`（只读账号）。
- Redis：部署 `oliver006/redis_exporter`，目标 `weknora-redis.knowledge-engine.svc:6379`（带密码）。
- 应用内 LLM/检索链路追踪：按需在管理台/环境变量开启 Langfuse（KB-M0-003 后评估）。

> 提醒：`networkpolicy.yaml` 已放行 `monitoring` namespace 访问 app:8080；
> 黑盒探测走 K8s Service 时不受 Pod 级 NetworkPolicy 影响，但 exporter 直连 Pod IP 的场景需要该规则。

## 与主系统同集群的资源配额建议

values-luyin.yaml 的 request 合计约 **1.65C / 3.2Gi**（app 500m/1Gi + docreader 500m/1Gi +
postgres 500m/1Gi + redis 100m/128Mi + frontend 50m/64Mi），limit 峰值合计约 **6.7C / 12.8Gi**。

建议对 knowledge-engine namespace 设置 ResourceQuota（防引擎失控挤占主系统）：

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: knowledge-engine-quota
  namespace: knowledge-engine
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "5"
    requests.storage: 200Gi
```

节点调度建议：docreader（解析高峰 CPU 密集）与 postgres 尽量落在独立节点池，
用 `nodeSelector`/`affinity` 与主系统（api-server/PG）错开——values-luyin.yaml 中对应字段
留空，待节点池命名确定后补充。

## 已知坑（部署时自查）

1. **ParadeDB 版本**：上游 chart 默认 `v0.18.9-pg17`，与 0.8.3 compose 栈实际使用的
   `v0.25.11-pg17` 不一致；values-luyin.yaml 已对齐后者。升级 WeKnora 版本时需复核
   compose 里的镜像 tag 并同步。
2. **app 更新策略**：`data-files` PVC 是 ReadWriteOnce，RollingUpdate 多副本会 Multi-Attach
   报错；values-luyin.yaml 已固定 `Recreate` + 单副本。
3. **模型出站**：app 需要访问 DeepSeek/百炼 API（出站），本套 NetworkPolicy 只收口入站，
   出站不受影响；若集群有全局出站策略（egress deny），需为 app 放行模型厂商 API 域名。
4. **SYSTEM_AES_KEY**：32 字节硬性要求 + 丢失不可恢复（见第 2 步警告）。
5. **release 名与标签耦合**：networkpolicy.yaml 的 selector 绑定 release 名 `weknora`。

## 本地栈运维手册

### 前端重建（品牌改动后必读）

改 `frontend/` 源码后需要重建 UI 镜像才能在 :8081 看到。本地开发机有三个环境坑，
完整命令序列（三者缺一不可）：

```bash
cd /Users/shi/Desktop/WeKnora && \
BUILDX_CONFIG=/tmp/buildx-cfg \
http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897 \
docker compose build frontend && \
docker compose up -d --force-recreate frontend
```

1. **buildx activity TCC 拦截**：默认 `~/.docker/buildx/activity/` 的状态文件 rename
   会被沙箱/security 拦截（`operation not permitted`），用 `BUILDX_CONFIG=/tmp/buildx-cfg`
   指到临时配置目录绕开。
2. **基础镜像拉取代理**：直连 docker.io 被 DNS 污染，62413 端口代理返回 Bad Gateway；
   必须显式 `http_proxy=http://127.0.0.1:7897`（与 git push 同款代理）。
3. **验证**：`curl -sS http://localhost:8081/ | grep title` 应为「都会美家知识库」。

### 模型 key 运维（占位 → 真实 key）

- 配置三件套见 `model-setup.sh`（幂等可重放：登录→建模型→debug 验证）。
- key 从不入库：真实 key 存宿主机 `luyin/tmp/wenknora`（不入 git），用
  `PUT /api/v1/models/{id}/credentials` 逐模型注入，服务器只回 `configured:true`。
- **默认 chat 模型坑**：裸调 `POST /knowledge-chat/{sid}`（不带 `summary_model_id`）的
  fallback 取 ListModels **无序结果**的第一个 KnowledgeQA 模型（PG heap order，
  不读 `is_default`）。行更新（含 PUT credentials）会使 tuple 后移、顺序翻转。
  生产语义要求"默认路径必须是活的"：确保可用 key 的模型排在前面，或在请求里显式
  带 `summary_model_id`；根治需 fork 补丁（fallback 优先 `is_default`），排期 M1。
