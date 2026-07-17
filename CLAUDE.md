# Working with the ComfyUI MCP server in this repo

This repo exposes a self-hosted ComfyUI backend through the `comfyui` MCP server
(see `.mcp.json` for its URL). The MCP server runs in **remote mode** — it talks
to ComfyUI over HTTP and does **not** share a filesystem with the MCP client.

## Downloading generated artifacts

Do not assume MCP tools that "save to disk" land anything on the client machine:
`get_image`'s `save_dir` writes to the **MCP server's** container filesystem, not
here. Use one of these instead.

- **Images** — `get_image` / `view_image` return the bytes **inline** over MCP,
  which reaches the client. This works only for images (PNG/JPEG/WebP).

- **Any artifact (images, video, audio)** — download over HTTP from ComfyUI's
  `/view` endpoint, published on port **8188** of the same host as the MCP server
  (the gateway allowlists it by source IP; no auth token needed):

  ```
  http://<host>:8188/view?filename=<name>&subfolder=<sub>&type=output
  ```

  `<host>` is the host from the `comfyui` server URL in `.mcp.json` with the port
  changed from `9100` to `8188`. Typical flow:

  1. `list_output_images` (MCP) → gives each result's `filename` and `subfolder`
     (`subfolder` is empty for top-level outputs, set for nested writes such as
     `SaveVideo` under `output/video/`).
  2. `curl -o result.<ext> "http://<host>:8188/view?filename=<name>&subfolder=<sub>&type=output"`

- **Push instead of pull** — `upload_output` (MCP) sends a result to S3, Azure
  Blob, an HTTP PUT URL, or HuggingFace.

See README.md ("Downloading generated content") for the full rationale.
