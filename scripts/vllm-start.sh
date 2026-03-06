#!/bin/bash
# /opt/llm-platform/scripts/vllm-start.sh
# Executed by: /etc/systemd/system/vllm.service
# Reads models.yaml and starts vLLM with the first enabled model.

set -euo pipefail

CONFIG_FILE="/opt/llm-platform/config/models.yaml"
LOG_FILE="/opt/llm-platform/logs/vllm/vllm.log"
VLLM_ENV="/root/vllm-env"

mkdir -p /opt/llm-platform/logs/vllm

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [vllm] $*" | tee -a "$LOG_FILE"
}

log "INFO =========================================="
log "INFO vLLM starting — reading $CONFIG_FILE"

# Parse first enabled model from models.yaml
read -r MODEL DTYPE MAX_MODEL_LEN GPU_MEM MAX_BATCHED CHUNKED HOST PORT < <(
  $VLLM_ENV/bin/python3 - <<'PYEOF'
import yaml, sys
with open("/opt/llm-platform/config/models.yaml") as f:
    cfg = yaml.safe_load(f)
model = next((m for m in cfg["models"] if m.get("enabled", False)), None)
if not model:
    print("ERROR: No enabled model found in models.yaml", file=sys.stderr)
    sys.exit(1)
chunked = "true" if model.get("enable_chunked_prefill", False) else "false"
print(
    model["id"],
    model.get("dtype", "bfloat16"),
    model.get("max_model_len", 32768),
    model.get("gpu_memory_utilization", 0.90),
    model.get("max_num_batched_tokens", 16384),
    chunked,
    cfg["server"]["host"],
    cfg["server"]["port"],
)
PYEOF
)

log "INFO Model    : $MODEL"
log "INFO dtype    : $DTYPE"
log "INFO ctx len  : $MAX_MODEL_LEN"
log "INFO GPU mem  : $GPU_MEM"
log "INFO batched  : $MAX_BATCHED"
log "INFO chunked  : $CHUNKED"
log "INFO endpoint : $HOST:$PORT"

# Set CUDA environment
# NOTE: ${LD_LIBRARY_PATH:-} safely handles unset variable in systemd clean environment
export CUDA_HOME=/usr/local/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export HF_TOKEN=$(grep HF_TOKEN /opt/llm-platform/.env | cut -d= -f2)

ARGS=(
  serve "$MODEL"
  --host "$HOST"
  --port "$PORT"
  --dtype "$DTYPE"
  --max-model-len "$MAX_MODEL_LEN"
  --gpu-memory-utilization "$GPU_MEM"
  --max-num-batched-tokens "$MAX_BATCHED"
)
[[ "$CHUNKED" == "true" ]] && ARGS+=(--enable-chunked-prefill)

log "INFO CMD: vllm ${ARGS[*]}"
log "INFO =========================================="

exec $VLLM_ENV/bin/vllm "${ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"