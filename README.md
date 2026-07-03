# image_gen_mcp

Self-hosted image generation for MCP clients (Claude Code, Claude Desktop, Cursor, ...):
two containers managed by one docker-compose file.

| Service      | Image                                | Port | Purpose                                  |
|--------------|--------------------------------------|------|------------------------------------------|
| `comfyui`    | `yanwk/comfyui-boot:cu130-slim-v2`   | —    | ComfyUI backend (web UI + API), internal only |
| `comfyui-mcp`| built from `mcp/Dockerfile`          | —    | [comfyui-mcp](https://github.com/artokun/comfyui-mcp) MCP server, streamable HTTP at `/mcp`, internal only |
| `gateway`    | `nginx:1.27-alpine`                  | 8188, 9100 | Single entry point: source-IP allowlist (`ALLOWED_SUBNET`) in front of both services |

## Requirements

- Docker + docker compose, NVIDIA container toolkit
- NVIDIA driver >= 580 (CUDA 13.0). For older drivers switch the image tag to
  `yanwk/comfyui-boot:cu126-slim`.
- A GPU with enough VRAM for your models (SDXL runs fine on a 12 GB RTX 3060).

## Quickstart

```bash
cp .env.example .env                  # then set MCP_TOKEN (openssl rand -hex 32)
docker compose up -d --build
./scripts/download_models.sh          # SDXL Base 1.0 (~6.9 GB) into models/checkpoints
```

- ComfyUI web UI: `http://<host>:8188`
- MCP endpoint:   `http://<host>:9100/mcp`

## Connecting an MCP client

Claude Code:

```bash
claude mcp add comfyui --transport http http://<host>:9100/mcp \
  --header "Authorization: Bearer <MCP_TOKEN>"
```

Or per-project via `.mcp.json`:

```json
{
  "mcpServers": {
    "comfyui": {
      "type": "http",
      "url": "http://<host>:9100/mcp",
      "headers": { "Authorization": "Bearer <MCP_TOKEN>" }
    }
  }
}
```

## Security

Two layers, both configured in `.env`:

- **Token auth**: the MCP server rejects requests without
  `Authorization: Bearer <MCP_TOKEN>` (HTTP 401).
- **Source-IP allowlist**: only the nginx `gateway` publishes ports; it denies
  requests from outside `ALLOWED_SUBNET` (HTTP 403) for both the MCP endpoint
  and the ComfyUI UI/API.
- On multi-homed hosts additionally set `BIND_IP` to the LAN interface IP so
  the ports are not published on other interfaces at all.

## Notes

- ComfyUI uses one GPU per instance. On a multi-GPU host, pin it with
  `device_ids: ["0"]` in the compose file (replacing `count: all`) if the other
  GPU is needed elsewhere.
- Models live in `./models/<category>/` (checkpoints, loras, vae, ...) and are
  bind-mounted into the container. `./output` holds generated images.
- Upgrade the MCP server by bumping `COMFYUI_MCP_VERSION` in `mcp/Dockerfile`
  and running `docker compose up -d --build comfyui-mcp`.
