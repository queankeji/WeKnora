#!/usr/bin/env bash
# =====================================================================
# luyin 知识引擎模型配置可重放脚本（KB-M0-003 产出）
# ---------------------------------------------------------------------
# 用途：在运行中的 WeKnora fork 栈上，以 API 方式完成
#       DeepSeek + 百炼(DashScope) 双 provider 模型配置，并触发
#       连通性 debug（真实 key 未配置时记录上游 401 错误语义）。
#
# 用法：
#   WEKNORA_BASE_URL=http://localhost:18080 \
#   WEKNORA_ADMIN_EMAIL=admin@luyin.internal \
#   WEKNORA_ADMIN_PASSWORD='<真实密码，或见 luyin/tmp/weknora_admin.env>' \
#   DEEPSEEK_API_KEY='sk-test-placeholder' \      # ⚠️ 占位 key，真实 key 到位后替换
#   DASHSCOPE_API_KEY='sk-test-placeholder' \     # ⚠️ 占位 key
#   bash deploy-luyin/model-setup.sh
#
# 约定：本脚本不写死任何真实密钥；占位 key 一律 sk-test-placeholder。
# 真实 key 到位后只需替换环境变量重跑（或走管理台 UI 更新凭据）。
# 幂等性：重复创建同名模型会报 duplicate —— 脚本先查列表，已存在则跳过。
# =====================================================================
set -euo pipefail

BASE_URL="${WEKNORA_BASE_URL:-http://localhost:18080}"
ADMIN_EMAIL="${WEKNORA_ADMIN_EMAIL:?need WEKNORA_ADMIN_EMAIL}"
ADMIN_PASSWORD="${WEKNORA_ADMIN_PASSWORD:?need WEKNORA_ADMIN_PASSWORD}"
DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-sk-test-placeholder}"   # ⚠️ 占位 key
DASHSCOPE_KEY="${DASHSCOPE_API_KEY:-sk-test-placeholder}" # ⚠️ 占位 key

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

say() { printf '\n==> %s\n' "$*"; }

# ---- 1. 登录（账号不存在时先注册；注册即成为新工作区 Owner）----
say "login as $ADMIN_EMAIL"
LOGIN_CODE=$(curl -sS -o "$TMPDIR_RUN/login.json" -w '%{http_code}' \
  -X POST "$BASE_URL/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
if [ "$LOGIN_CODE" != "200" ]; then
  say "login failed ($LOGIN_CODE), try register"
  curl -sS -X POST "$BASE_URL/api/v1/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"luyin-admin\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" >/dev/null
  curl -sS -o "$TMPDIR_RUN/login.json" \
    -X POST "$BASE_URL/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}"
fi
TOKEN=$(python3 -c "import json;print(json.load(open('$TMPDIR_RUN/login.json'))['token'])")
AUTH="Authorization: Bearer $TOKEN"
say "token acquired (len=${#TOKEN})"

# ---- 2. 幂等创建模型（已存在同名则跳过）----
create_model() { # $1=name $2=display $3=type $4=json-parameters
  local name="$1" display="$2" mtype="$3" params="$4"
  local exists
  exists=$(curl -sS "$BASE_URL/api/v1/models?type=$3" -H "$AUTH" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(any(m['name']=='$name' for m in d.get('data',[])))")
  if [ "$exists" = "True" ]; then
    say "model '$name' already exists, skip"
    return 0
  fi
  curl -sS -X POST "$BASE_URL/api/v1/models" -H "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\",\"display_name\":\"$display\",\"type\":\"$mtype\",\"source\":\"remote\",\"parameters\":$params}" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print('created:',d['data']['name'],'id:',d['data']['id'])"
}

say "create DeepSeek chat model (key: ${DEEPSEEK_KEY:0:8}...)"
create_model "deepseek-chat" "DeepSeek Chat (luyin)" "KnowledgeQA" \
  "{\"base_url\":\"https://api.deepseek.com/v1\",\"api_key\":\"$DEEPSEEK_KEY\",\"provider\":\"deepseek\"}"

say "create DashScope chat model (key: ${DASHSCOPE_KEY:0:8}...)"
create_model "qwen-plus" "Qwen Plus via DashScope (luyin)" "KnowledgeQA" \
  "{\"base_url\":\"https://dashscope.aliyuncs.com/compatible-mode/v1\",\"api_key\":\"$DASHSCOPE_KEY\",\"provider\":\"aliyun\"}"

say "create DashScope text embedding model"
create_model "text-embedding-v4" "DashScope text-embedding-v4 (luyin)" "Embedding" \
  "{\"base_url\":\"https://dashscope.aliyuncs.com/compatible-mode/v1\",\"api_key\":\"$DASHSCOPE_KEY\",\"provider\":\"aliyun\",\"embedding_parameters\":{\"dimension\":1024,\"truncate_prompt_tokens\":8192}}"

say "create DashScope MULTIMODAL embedding model (luyin M2 视觉召回核心)"
# 百炼原生多模态协议（dashscope-embeddings）：目录 match "multimodal-embedding*"，
# 旧名 multimodal-embedding-one-peace-v1 同样命中该通配。
create_model "multimodal-embedding-v1" "DashScope multimodal-embedding-v1 (luyin 视觉召回)" "Embedding" \
  "{\"base_url\":\"https://dashscope.aliyuncs.com/compatible-mode/v1\",\"api_key\":\"$DASHSCOPE_KEY\",\"provider\":\"aliyun\",\"embedding_parameters\":{\"dimension\":1024}}"

# ---- 3. 连通性 debug（占位 key 时代：预期上游 401，即配置链路全通）----
debug_model() { # $1=model name $2=input form field
  local name="$1"
  local id
  id=$(curl -sS "$BASE_URL/api/v1/models" -H "$AUTH" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(next(m['id'] for m in d['data'] if m['name']=='$name'))")
  say "debug '$name' (id=$id)"
  curl -sS -X POST "$BASE_URL/api/v1/models/$id/debug" -H "$AUTH" -F "input=ping" \
    | python3 -c "import json,sys;d=json.load(sys.stdin)['data'];print('ok:',d['ok'],'| elapsed_ms:',d['elapsed_ms'],'| error:',(d.get('error') or '(none)')[:200])"
}

debug_model "deepseek-chat"
debug_model "qwen-plus"
debug_model "text-embedding-v4"
debug_model "multimodal-embedding-v1"

# ---- 4. 多模态图片链路 debug（生成 8x8 测试 PNG，验证图片输入被接受）----
say "debug multimodal-embedding-v1 with IMAGE input"
MM_ID=$(curl -sS "$BASE_URL/api/v1/models" -H "$AUTH" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(next(m['id'] for m in d['data'] if m['name']=='multimodal-embedding-v1'))")
python3 - <<'PYIMG'
import struct, zlib
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
w = h = 8
raw = b''.join(b'\x00' + bytes([200, 60, 60] * w) for _ in range(h))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open('/tmp/weknora_mm_test.png', 'wb').write(png)
print('test image written:', len(png), 'bytes')
PYIMG
curl -sS -X POST "$BASE_URL/api/v1/models/$MM_ID/debug" -H "$AUTH" \
  -F "file=@/tmp/weknora_mm_test.png" \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['data'];print('ok:',d['ok'],'| error:',(d.get('error') or '(none)')[:200])"
rm -f /tmp/weknora_mm_test.png

say "done. 真实 key 到位后：重跑本脚本并替换 DEEPSEEK_API_KEY / DASHSCOPE_API_KEY，或经管理台 UI 更新凭据（模型管理 → 对应模型 → 凭据）。"
