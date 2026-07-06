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

## Local Capabilities

The comfyui-mcp server exposes a broad set of tools that run entirely on the local GPU — no cloud account or external API key required.

### Image Generation

| Tool | Description |
|------|-------------|
| `generate_image` | Text-to-image (txt2img) — builds the workflow, auto-selects checkpoint |
| `generate_with_controlnet` | Pose, depth, or canny-conditioned generation from a preprocessed map |
| `generate_with_ip_adapter` | Style/subject transfer guided by a reference image |
| `remove_background` | BiRefNet matting — returns transparent RGBA cutout |
| `upscale_image` | ESRGAN super-resolution (2x / 4x) |
| `create_workflow` | Template builder for txt2img, img2img, upscale, inpaint, controlnet, ip_adapter |

### Video Generation

| Tool | Description |
|------|-------------|
| `generate_video` | LTX-2.3 text-to-video and image-to-video (distilled model, ~8 steps) |

### Audio Generation

| Tool | Description |
|------|-------------|
| `generate_audio` | ACE Step 1.5 or Stable Audio 3 text-to-audio |

### Workflow Lifecycle

- **Submit & monitor:** `enqueue_workflow`, `get_job_status`, `get_history`
- **Reproduce:** `rerun_generation`, `regenerate` (with parameter overrides)
- **Validate:** `validate_workflow` — dry-run check before execution
- **Inspect:** `analyze_workflow`, `visualize_workflow` — structured summary or Mermaid diagram
- **Edit:** `modify_workflow` — surgical ops (set input, add/remove/connect nodes)
- **Round-trip:** `workflow_to_dsl` / `dsl_to_workflow` — compact human-readable format
- **Surgical extraction:** `slice_workflow` / `strip_workflow` — extract one pipeline from a toggle-template monolith

### Model & Node Management

- **Download models:** `download_model` (any URL), `download_civitai_model` (CivitAI id)
- **Search:** `search_models` (HuggingFace)
- **Custom nodes:** `install_custom_node`, `update_custom_node`, `fix_custom_node` via ComfyUI-Manager
- **Installer packs:** 54 bundled packs covering ANIMA, ERNIE, Ideogram, Krea 2, LTX-2.3, Qwen-Image, WAN 2.2, Z-Image families — install models + custom nodes + ready-to-run workflow in one step via `apply_manifest`
- **Built-in skills:** 31 domain-expertise skills (prompt engineering, color correction, debugging, LoRA training, per-family setup guides)

### File & Asset Handling

- **Upload:** `upload_image`, `upload_video`, `upload_audio` — stage inputs for loaders
- **Chain stages:** `stage_output_as_input` — wire one stage's output into the next stage's input
- **Inspect output:** `list_output_images` — recursive scan of images and videos
- **View / fetch:** `view_image` (inline), `get_image` (save to disk)
- **Convert:** `convert_image` — re-encode to PNG, JPEG, or WebP
- **Export:** `upload_output` — push results to S3, Azure Blob, HTTP PUT, or HuggingFace

### Utilities

- `clear_vram` — unload cached models between runs
- Queue management: `clear_queue`, `cancel_job`, `move_queued_job`, `edit_queued_job`
- Provenance: `lock_workflow` / `verify_workflow_lock` — SHA-256 model hashes + git commit pins
- Debug: `bisect_start/good/bad` — binary search for a broken custom node
- Custom node authoring: `scaffold_custom_node`, `verify_custom_node`, `publish_custom_node`

## Notes

- ComfyUI uses one GPU per instance. On a multi-GPU host, pin it with
  `device_ids: ["0"]` in the compose file (replacing `count: all`) if the other
  GPU is needed elsewhere.
- Models live in `./models/<category>/` (checkpoints, loras, vae, ...) and are
  bind-mounted into the container. `./output` holds generated images.
- Upgrade the MCP server by bumping `COMFYUI_MCP_VERSION` in `mcp/Dockerfile`
  and running `docker compose up -d --build comfyui-mcp`.
