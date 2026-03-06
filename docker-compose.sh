# /opt/llm-platform/docker-compose.yml
# vLLM runs as a systemd service on the HOST — only WebUI is here.
#
# Manage vLLM:   sudo systemctl start|stop|restart vllm
# Reload model:  ./scripts/reload.sh
# WebUI:         docker compose up -d

name: llm-platform

services:
  webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"   # Allows container to reach host vLLM

    ports:
      - "0.0.0.0:${WEBUI_PORT:-3000}:8080"    # All interfaces — firewall controls access

    environment:
      OPENAI_API_BASE_URL: http://host.docker.internal:8000/v1  # vLLM on host
      OPENAI_API_KEY: EMPTY
      WEBUI_AUTH: "true"
      ENABLE_SIGNUP: "false"                   # Disabled — admin creates users manually
      GLOBAL_LOG_LEVEL: INFO

    volumes:
      - open_webui_data:/app/backend/data
      - ./logs/webui:/app/backend/logs

    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

volumes:
  open_webui_data: