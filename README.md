# image_gen_mcp

Self-hosted image generation for MCP clients (Claude Code, Claude Desktop, Cursor, ...):
containers managed by one docker-compose file.

| Service            | Image                                | Port | Purpose                                  |
|--------------------|--------------------------------------|------|------------------------------------------|
| `comfyui`          | `yanwk/comfyui-boot:cu130-slim-v2`   | —    | ComfyUI backend (web UI + API), GPU0, internal only |
| `comfyui-mcp`      | built from `mcp/Dockerfile`          | —    | [comfyui-mcp](https://github.com/artokun/comfyui-mcp) MCP server (our fork [`padeler/comfyui-mcp`](https://github.com/padeler/comfyui-mcp)), streamable HTTP at `/mcp`, internal only |
| `comfyui-gpu1`     | `yanwk/comfyui-boot:cu130-slim-v2`   | —    | Second ComfyUI backend, pinned to GPU1, internal only |
| `comfyui-mcp-gpu1` | built from `mcp/Dockerfile`          | —    | MCP server for `comfyui-gpu1`, streamable HTTP at `/mcp`, internal only |
| `gateway`          | `nginx:1.27-alpine`                  | 8188, 9100, 8189, 9101 | Single entry point: source-IP allowlist (`ALLOWED_SUBNET`) in front of all four backend services |

The GPU1 pair is behind the `gpu1` compose profile. `.env.example` sets
`COMPOSE_PROFILES=gpu1`, so plain `docker compose up -d` starts all five
services by default on a two-GPU host — comment that line out on a
single-GPU host to fall back to just `comfyui`/`comfyui-mcp`/`gateway`. See
[Parallel GPUs](#parallel-gpus) for details.

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

## Parallel GPUs

On a host with two GPUs, `comfyui-gpu1` + `comfyui-mcp-gpu1` are a second,
independent instance pinned to GPU1 — each ComfyUI process is still
single-GPU, but the two can each serve one generation at the same time. It's
a second MCP endpoint, not automatic load balancing: you (or the client)
choose which GPU's tool to call for a given job.

Enabled by default (`COMPOSE_PROFILES=gpu1` in `.env.example`) once
`COMFYUI_PUBLIC_URL_GPU1` is set:

```bash
docker compose up -d --build
```

To bring up just the GPU1 pair without restarting GPU0, or on a host where
`COMPOSE_PROFILES` isn't set:

```bash
docker compose --profile gpu1 up -d --build
```

- ComfyUI web UI (GPU1): `http://<host>:8189`
- MCP endpoint (GPU1):   `http://<host>:9101/mcp`

Add it as a second server in `.mcp.json`:

```json
{
  "mcpServers": {
    "comfyui": {
      "type": "http",
      "url": "http://<host>:9100/mcp",
      "headers": { "Authorization": "Bearer <MCP_TOKEN>" }
    },
    "comfyui-gpu1": {
      "type": "http",
      "url": "http://<host>:9101/mcp",
      "headers": { "Authorization": "Bearer <MCP_TOKEN>" }
    }
  }
}
```

Both instances share the same `./models`, `./output`, `./input`, `./user`
bind mounts, so no model duplication is needed — just make sure the host
actually has two GPUs before enabling the profile (`nvidia-smi -L`).

## Downloading generated content

> The MCP server now **advertises this download guidance automatically**: our
> fork populates the MCP `instructions` field (returned on `initialize`), so any
> connecting client learns the `/view` download path without per-repo docs. The
> concrete URL comes from `COMFYUI_PUBLIC_URL` (set in `.env`, see below). This
> section is the human-facing version of the same thing.

The MCP server runs in **remote mode** (it reaches ComfyUI over HTTP, `COMFYUI_PATH`
is unset). Two consequences follow for retrieving generated artifacts from a
different host than the one running the stack:

- MCP tools that "save to disk" (`get_image`'s `save_dir`, default
  `/tmp/comfyui-images/`) write to the **MCP container's** filesystem on the
  server, not the client — do not rely on them for remote download.
- `get_image` / `view_image` return image bytes **inline** over MCP, which does
  reach a remote client — but only for images (PNG/JPEG/WebP). Video and audio
  have no inline path.

The universal, artifact-type-agnostic way to download any output is ComfyUI's
own HTTP `/view` endpoint, already published by the gateway on port `8188`
(source-IP allowlisted, no bearer token required):

```
http://<host>:8188/view?filename=<name>&subfolder=<sub>&type=output
```

Typical flow from a remote client — list outputs via MCP, then fetch over HTTP:

1. `list_output_images` (MCP) → gives each result's `filename` and `subfolder`.
2. `curl -o result.png "http://<host>:8188/view?filename=<name>&subfolder=<sub>&type=output"`

`subfolder` is empty for top-level outputs and set for nested writes (e.g.
`SaveVideo` writes under `output/video/`). This works identically for `.png`,
`.mp4`, `.wav`, etc.

For pushing outputs elsewhere instead of pulling, `upload_output` (MCP) sends a
result to S3, Azure Blob, an HTTP PUT URL, or HuggingFace.

## Security

Two layers, both configured in `.env`:

- **Token auth**: the MCP server rejects requests without
  `Authorization: Bearer <MCP_TOKEN>` (HTTP 401).
- **Source-IP allowlist**: only the nginx `gateway` publishes ports; it denies
  requests from outside `ALLOWED_SUBNET` (HTTP 403) for both the MCP endpoint
  and the ComfyUI UI/API.
- On multi-homed hosts additionally set `BIND_IP` to the LAN interface IP so
  the ports are not published on other interfaces at all.

## MCP server fork

The `comfyui-mcp` service is built from our fork
[`padeler/comfyui-mcp`](https://github.com/padeler/comfyui-mcp)
(branch `feat/public-download-instructions`) rather than the upstream npm
package. `mcp/Dockerfile` builds it in two stages and pins it to an immutable
commit via the `COMFYUI_MCP_REF` build arg.

**Why the fork exists.** In remote mode (this deployment), a fresh MCP client had
no way to learn how to download generated artifacts: `get_image`'s `save_dir`
writes to the MCP *server's* filesystem, only images return inline, and the
reliable HTTP path (ComfyUI's `/view` endpoint) was undocumented over the MCP
channel itself. The fork makes that guidance travel *with* the server.

**What changed** (three small, surgical edits — see the branch for the diff):

- **`COMFYUI_PUBLIC_URL`** — a new env var for the client-reachable base URL of
  ComfyUI (e.g. `http://192.168.1.2:8188`), distinct from `COMFYUI_URL`, which is
  the container-internal address (`http://comfyui:8188`) that clients can't reach.
  Exposed via a `getComfyUIPublicUrl()` helper that falls back to the API base
  URL when unset.
- **MCP `instructions`** — the server now populates the `instructions` field of
  the `initialize` response with concrete download guidance (the `/view` URL built
  from `COMFYUI_PUBLIC_URL`). MCP clients surface `instructions` automatically on
  connect, so any client in any repo learns the download path with no per-repo
  documentation.
- **`.env.example`** — documents the new `COMFYUI_PUBLIC_URL` variable.

These changes are upstream-friendly and additive (no behavior change when
`COMFYUI_PUBLIC_URL` is unset); the intent is to contribute them back to
[`artokun/comfyui-mcp`](https://github.com/artokun/comfyui-mcp).

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

- ComfyUI uses one GPU per instance (`comfyui` is pinned to `device_ids: ["0"]`
  in the compose file). See [Parallel GPUs](#parallel-gpus) to also use a
  second GPU via the `comfyui-gpu1` / `comfyui-mcp-gpu1` pair.
- Models live in `./models/<category>/` (checkpoints, loras, vae, ...) and are
  bind-mounted into the container. `./output` holds generated images.
- The MCP server is built from our fork
  [`padeler/comfyui-mcp`](https://github.com/padeler/comfyui-mcp) (adds
  `COMFYUI_PUBLIC_URL` + the auto-advertised download `instructions`). Upgrade it
  by bumping `COMFYUI_MCP_REF` (a commit SHA) in `mcp/Dockerfile` and running
  `docker compose up -d --build comfyui-mcp`.
