# Bugs

- [x] ComfyUI download seems to be storing locally, so hosts accessing the MCP service from remote cannot use the download command to get generated content. Investigate the issue.
    - when testing from the project folder (this folder) with the the mcp service running on the remote host (192.168.1.2) the output is writen in ./output. However this is due to the fact that this host (pollux) and the mcp host (castor) share the same /home filesystem.
    - The correct test for the service is to be able to download the generated artifacts through http (mcp or otherwise)
    - [x] All generated content should be downloadable (or documented on how to do this) through the MCP service
    - Root cause: MCP runs in remote mode (COMFYUI_PATH unset); `get_image` save_dir
      writes to the MCP container's own /tmp, and inline return only covers images.
      The universal download path — ComfyUI's HTTP `/view` endpoint, already exposed
      by the gateway on 8188 — was not discoverable through the MCP channel itself,
      so a fresh client in any repo had no way to learn it.
    - Resolution: forked comfyui-mcp → padeler/comfyui-mcp
      (branch feat/public-download-instructions). Added COMFYUI_PUBLIC_URL and
      populated the MCP server `instructions` field with concrete /view download
      guidance. Clients surface `instructions` automatically on initialize, so the
      guidance now travels WITH the server to any repo/client — no per-repo docs.
      mcp/Dockerfile builds the fork (multi-stage, pinned to a commit SHA);
      docker-compose + .env set COMFYUI_PUBLIC_URL. Verified end-to-end: initialize
      response returns the instructions with the correct public /view URL, and a
      raw GET /view returns HTTP 200 + full bytes.

# Follow-ups

- [ ] Open a PR upstream to `artokun/comfyui-mcp` with the fork changes
  (`COMFYUI_PUBLIC_URL` + MCP `instructions` for artifact download). Branch:
  `feat/public-download-instructions` on `padeler/comfyui-mcp`. The changes are
  additive and behavior-preserving when `COMFYUI_PUBLIC_URL` is unset.
