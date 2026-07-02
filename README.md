# image_gen_mcp

Self-hosted image generation for MCP clients (Claude Code, Claude Desktop, Cursor, ...):
two containers managed by one docker-compose file.

| Service      | Image                                | Port | Purpose                                  |
|--------------|--------------------------------------|------|------------------------------------------|
| `comfyui`    | `yanwk/comfyui-boot:cu130-slim-v2`   | 8188 | ComfyUI backend (web UI + API)            |
| `comfyui-mcp`| built from `mcp/Dockerfile`          | 9100 | [comfyui-mcp](https://github.com/artokun/comfyui-mcp) MCP server, streamable HTTP at `/mcp` |

## Requirements

- Docker + docker compose, NVIDIA container toolkit
- NVIDIA driver >= 580 (CUDA 13.0). For older drivers switch the image tag to
  `yanwk/comfyui-boot:cu126-slim`.
- A GPU with enough VRAM for your models (SDXL runs fine on a 12 GB RTX 3060).

## Quickstart

```bash
docker compose up -d --build
./scripts/download_models.sh          # SDXL Base 1.0 (~6.9 GB) into models/checkpoints
```

- ComfyUI web UI: `http://<host>:8188`
- MCP endpoint:   `http://<host>:9100/mcp`

## Connecting an MCP client

Claude Code:

```bash
claude mcp add comfyui --transport http http://<host>:9100/mcp
```

Or per-project via `.mcp.json`:

```json
{
  "mcpServers": {
    "comfyui": { "type": "http", "url": "http://<host>:9100/mcp" }
  }
}
```

## Notes

- The MCP endpoint is **unauthenticated** (`COMFYUI_MCP_ALLOW_UNAUTH=1`) — intended
  for a trusted private LAN only. To add auth, replace that env var with
  `COMFYUI_MCP_HTTP_TOKEN=<secret>` in `docker-compose.yml` and send
  `Authorization: Bearer <secret>` from clients.
- ComfyUI uses one GPU per instance. On a multi-GPU host, pin it with
  `device_ids: ["0"]` in the compose file (replacing `count: all`) if the other
  GPU is needed elsewhere.
- Models live in `./models/<category>/` (checkpoints, loras, vae, ...) and are
  bind-mounted into the container. `./output` holds generated images.
- Upgrade the MCP server by bumping `COMFYUI_MCP_VERSION` in `mcp/Dockerfile`
  and running `docker compose up -d --build comfyui-mcp`.
