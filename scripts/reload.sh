#!/bin/bash
# /opt/llm-platform/scripts/reload.sh
# Edit config/models.yaml then run this script to apply changes.
# Usage: cd /opt/llm-platform && ./scripts/reload.sh

set -euo pipefail

LOG_FILE="/opt/llm-platform/logs/vllm/reload.log"
mkdir -p /opt/llm-platform/logs/vllm

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [reload] $*" | tee -a "$LOG_FILE"
}

log "INFO ============================================"
log "INFO vLLM config reload triggered by: $(whoami)"
log "INFO ============================================"

ACTIVE_MODEL=$(grep -A1 'enabled: true' /opt/llm-platform/config/models.yaml \
  | grep 'id:' | awk '{print $2}')
log "INFO Active model from config: ${ACTIVE_MODEL:-unknown}"

log "INFO Stopping vllm service..."
sudo systemctl stop vllm

log "INFO Resetting failure counter..."
sudo systemctl reset-failed vllm

log "INFO Starting vllm service..."
sudo systemctl start vllm

log "INFO Waiting for vLLM to become healthy (up to 300s)..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:8000/v1/models > /dev/null 2>&1; then
    log "INFO vLLM is healthy after $((i * 5))s."
    log "INFO Models available:"
    curl -s http://localhost:8000/v1/models | \
      python3 -c "import sys,json; [print('  - ' + m['id']) \
      for m in json.load(sys.stdin)['data']]" | tee -a "$LOG_FILE"
    log "INFO Reload complete."
    exit 0
  fi
  sleep 5
done

log "ERROR vLLM did not become healthy within 300s."
log "ERROR Check: journalctl -u vllm -n 50"
exit 1