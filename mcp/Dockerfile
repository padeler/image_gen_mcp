FROM node:22-bookworm-slim

# Pin the version; upgrade deliberately by bumping this and rebuilding.
ARG COMFYUI_MCP_VERSION=0.24.1
RUN npm install -g comfyui-mcp@${COMFYUI_MCP_VERSION}

EXPOSE 9100
ENTRYPOINT ["comfyui-mcp", "--http", "--host", "0.0.0.0", "--port", "9100"]
