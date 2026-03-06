# LLM Platform — v1

> Production deployment of **Meta Llama 3.1 8B Instruct** using **vLLM** inference engine and **Open WebUI** on an NVIDIA H200 GPU server.

---

## Stack

| Component | Technology | Version |
|---|---|---|
| Inference Engine | vLLM | 0.16.0+ |
| LLM | Meta Llama 3.1 8B Instruct | — |
| Web Interface | Open WebUI | latest |
| GPU | NVIDIA H200 (143 GB HBM3e) | — |
| GPU Driver | NVIDIA Driver | 590.48.01 |
| CUDA | CUDA Toolkit | 12.8 |
| OS | Ubuntu | 22.04 LTS |
| Container Runtime | Docker + NVIDIA Container Toolkit | — |
| Process Manager | systemd | — |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Ubuntu 22.04 Host                  │
│                                                     │
│  systemd: vllm.service                              │
│  └─ /root/vllm-env/bin/vllm serve                   │
│     └─ reads config/models.yaml                     │
│     └─ logs  logs/vllm/vllm.log                     │
│     └─ API   0.0.0.0:8000  (OpenAI-compatible)      │
│                    │                                │
│             NVIDIA H200 GPU                         │
│                                                     │
│  systemd: llm-webui.service                         │
│  └─ Docker: open-webui container                    │
│     └─ UI    0.0.0.0:3000                           │
│     └─ connects to vLLM via host.docker.internal    │
└─────────────────────────────────────────────────────┘
```

vLLM runs directly on the **host** (not in Docker) to avoid CUDA-in-container library conflicts with the H200 driver stack.

---

## Repository Structure

```
/
├── config/
│   └── models.yaml          # LLM model config — edit to switch models
├── scripts/
│   ├── vllm-start.sh        # systemd entrypoint — reads models.yaml
│   └── reload.sh            # hot-reload vLLM after config change
├── docker-compose.yml       # Open WebUI container
├── .env.example             # Environment variable template
└── README.md
```

> ⚠️ `.env` contains secrets and is **not committed**. Copy `.env.example` and fill in your values.

---

## Prerequisites

- NVIDIA H200 GPU (or any Hopper-class GPU with 40 GB+ VRAM)
- Ubuntu 22.04 LTS
- NVIDIA Driver 550+ (`nvidia-smi` must work)
- CUDA Toolkit 12.x at `/usr/local/cuda-12.x`
- Docker Engine 24.0+ with NVIDIA Container Toolkit
- Python 3.10+
- HuggingFace account with access to [Meta Llama 3.1 8B Instruct](https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct)

---

## Setup

### 1. Clone the repository

```bash
git clone <repo-url> /opt/llm-platform
cd /opt/llm-platform
```

### 2. Configure environment

```bash
cp .env.example .env
vi .env   # Set HF_TOKEN to your HuggingFace API token
```

### 3. Set up Python virtualenv and install vLLM

```bash
python3 -m venv /root/vllm-env
source /root/vllm-env/bin/activate
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
pip install vllm pyyaml
```

### 4. Set CUDA environment variables

```bash
cat >> ~/.bashrc << 'EOF'
export CUDA_HOME=/usr/local/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
EOF
source ~/.bashrc
```

### 5. Make scripts executable

```bash
chmod +x scripts/vllm-start.sh scripts/reload.sh
```

### 6. Install systemd services

```bash
# vLLM service
sudo tee /etc/systemd/system/vllm.service << 'EOF'
[Unit]
Description=vLLM Inference Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llm-platform
ExecStart=/opt/llm-platform/scripts/vllm-start.sh
Restart=on-failure
RestartSec=10
StartLimitBurst=3
StartLimitIntervalSec=60
StandardOutput=append:/opt/llm-platform/logs/vllm/vllm.log
StandardError=append:/opt/llm-platform/logs/vllm/vllm.log
KillSignal=SIGTERM
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF

# WebUI service
sudo tee /etc/systemd/system/llm-webui.service << 'EOF'
[Unit]
Description=LLM Platform WebUI
Requires=docker.service
After=docker.service vllm.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/llm-platform
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vllm.service llm-webui.service
sudo systemctl start vllm.service
# Wait ~3 minutes for model to load, then:
sudo systemctl start llm-webui.service
```

### 7. Configure log rotation

```bash
sudo tee /etc/logrotate.d/llm-platform << 'EOF'
/opt/llm-platform/logs/vllm/*.log
/opt/llm-platform/logs/webui/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    dateext
    dateformat -%Y%m%d
}
EOF
```

### 8. Verify

```bash
# vLLM API
curl -s http://localhost:8000/v1/models | python3 -m json.tool

# WebUI container
docker compose ps

# WebUI → vLLM connectivity
docker exec open-webui curl -sf http://host.docker.internal:8000/v1/models
```

Open WebUI is available at `http://<server-ip>:3000`.

---

## Configuration

### Switching Models

Edit `config/models.yaml` — set `enabled: true` on the desired model, `enabled: false` on all others. Then run:

```bash
./scripts/reload.sh
```

The reload script will stop vLLM, restart it with the new model, and wait until the API is healthy before returning.

### models.yaml Parameters

| Parameter | Description | Default |
|---|---|---|
| `id` | HuggingFace model ID | — |
| `enabled` | Activate this model (one at a time) | `false` |
| `dtype` | Tensor type — `bfloat16` optimal for H200 | `bfloat16` |
| `max_model_len` | Max context window in tokens | `32768` |
| `gpu_memory_utilization` | Fraction of VRAM allocated to vLLM | `0.90` |
| `max_num_batched_tokens` | Max tokens per batch | `16384` |
| `enable_chunked_prefill` | Better latency on long prompts | `true` |

---

## Operations

| Action | Command |
|---|---|
| Start all services | `sudo systemctl start vllm && sudo systemctl start llm-webui` |
| Stop all services | `sudo systemctl stop llm-webui && sudo systemctl stop vllm` |
| Restart vLLM | `sudo systemctl restart vllm` |
| Switch model | Edit `config/models.yaml` → `./scripts/reload.sh` |
| Health check | `curl -s http://localhost:8000/v1/models` |
| Live log | `tail -f /opt/llm-platform/logs/vllm/vllm.log` |
| GPU status | `nvidia-smi` |
| Fix crash loop | `sudo systemctl reset-failed vllm && sudo systemctl start vllm` |
| Update WebUI | `docker compose pull && docker compose up -d` |

---

## Logs

| Log | Path |
|---|---|
| vLLM inference + startup | `logs/vllm/vllm.log` |
| Model reload events | `logs/vllm/reload.log` |
| WebUI application logs | `logs/webui/` |
| systemd journal | `journalctl -u vllm -f` |

Logs are rotated daily, compressed, and retained for 90 days. The `logs/vllm/vllm.log` file is the primary source for SIEM forwarding.

---

## Security Notes

- `.env` is excluded from version control via `.gitignore` — never commit secrets
- Open WebUI has authentication enabled (`WEBUI_AUTH: true`)
- Self-registration is disabled (`ENABLE_SIGNUP: false`) — admin must create all users
- Both services bind to `0.0.0.0` — restrict access via firewall to trusted CIDRs
- vLLM API (port 8000) should not be exposed externally — place NGINX in front for production external access

---

## .gitignore

```
.env
logs/
__pycache__/
*.pyc
```

---

## Roadmap

| Version | Planned Features |
|---|---|
| **v1** ✅ | Llama 3.1 8B · vLLM · Open WebUI · systemd · logging |


---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `nvidia-smi` not found | `sudo apt install -y nvidia-utils-590` |
| Driver not loaded after reboot | `sudo apt install -y dkms nvidia-dkms-590 && sudo dkms autoinstall` |
| Error 803 CUDA mismatch | `pip install torch --index-url https://download.pytorch.org/whl/cu128` |
| `LD_LIBRARY_PATH: unbound variable` | Ensure script uses `${LD_LIBRARY_PATH:-}` on export line |
| vllm.service crash loop | `sudo systemctl reset-failed vllm && sudo systemctl start vllm` |
| WebUI can't reach vLLM | `docker exec open-webui curl http://host.docker.internal:8000/v1/models` |
| No model enabled error | Set `enabled: true` on exactly one model in `config/models.yaml` |
| MIG mode blocking GPU | `sudo nvidia-smi -i 0 -mig 0` then reboot |

---

*LTIMindtree — Infrastructure Business Unit · Internal Use Only*