# Build our fork (padeler/comfyui-mcp), which adds COMFYUI_PUBLIC_URL + MCP
# `instructions` so remote clients learn how to download generated artifacts over
# ComfyUI's /view HTTP endpoint. Pin to an immutable commit; upgrade by bumping
# COMFYUI_MCP_REF and rebuilding.
#
# Two stages: the builder clones + compiles (TypeScript → dist) and packs a
# tarball; the runtime installs only that tarball (production deps, no git/
# toolchain, no dev deps). Installing the fork directly via
# `npm install -g github:...` fails because npm's git-dep prep can't run the
# package's `prepare` (tsc) reliably — hence the explicit build here.

FROM node:22-bookworm-slim AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ARG COMFYUI_MCP_REF=af3b6f174352ea46c1f80c0370396338dbf16739
WORKDIR /src
RUN git clone https://github.com/padeler/comfyui-mcp.git . \
    && git checkout "${COMFYUI_MCP_REF}" \
    && npm ci \
    && npm run build \
    && npm pack

FROM node:22-bookworm-slim
COPY --from=build /src/comfyui-mcp-*.tgz /tmp/
RUN npm install -g /tmp/comfyui-mcp-*.tgz \
    && rm -f /tmp/comfyui-mcp-*.tgz

EXPOSE 9100
ENTRYPOINT ["comfyui-mcp", "--http", "--host", "0.0.0.0", "--port", "9100"]
