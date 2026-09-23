# mcl-git
#
# Git over the mesh: bare repositories cloned, fetched and pushed through
# org-namespaced mesh procedures.
#
# ⚠ ONE OTP, 28.4.3, PINNED BY TAG AND DIGEST, here and in `lint.yml' beside it
# (mcl_git_service_tests checks both). `erlang:28-alpine' floats: when Docker Hub
# moved it on 2026-09-22 the next deploy of a sibling shipped OTP 28.5 while CI
# tested something else. hexpm's image, because Docker's own `erlang' publishes
# no 28.4.3; Alpine 3.22.6, the same release as the runtime stage below.
FROM docker.io/hexpm/erlang:28.4.3-alpine-3.22.6@sha256:3815b99f486c2509baf556045bca0c5fc1c3ee50fb50a80590534f22cb48736c AS builder
WORKDIR /build

# macula ships a QUIC NIF. MACULA_FORCE_SOURCE_BUILD builds it here rather than
# fetching a prebuilt binary linked against glibc, which loads on the build
# host and fails on alpine at runtime.
#
# No database NIF: mcl_om 0.27 dropped barrel_docdb, and mcl-git has no read model
# of its own that would bring it back.
RUN apk add --no-cache git curl bash build-base cmake perl linux-headers
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
ENV RUSTFLAGS="-C target-feature=-crt-static"
ENV MACULA_FORCE_SOURCE_BUILD=1

# rebar3 pinned to a release and its sha256.
RUN curl -fsSL https://github.com/erlang/rebar3/releases/download/3.27.0/rebar3 \
        -o /usr/local/bin/rebar3 \
    && echo "af85aab41f9fd74bdd6341ebdf6fe9c88077aab9f8eac82371583fa02f2b0bdf  /usr/local/bin/rebar3" \
        | sha256sum -c - \
    && chmod +x /usr/local/bin/rebar3

# Dependencies resolve from rebar.config alone, so this layer survives every
# change to config/ and apps/.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY apps ./apps
# relx copies bin/git-remote-mesh from rel/overlay; without this the image
# ships no helper.
COPY rel ./rel
RUN rebar3 as prod release

FROM docker.io/alpine:3.22
# Links the package to the repository on ghcr: without it the package is an
# orphan that does not inherit the repository's visibility.
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-git"
# ⚠ git: EVERY procedure that moves code runs `git upload-pack' or `git
# receive-pack'. Without it each clone, fetch and push answers `git_failed'
# while /health stays green. Neither image this was ported from installed it:
# hecate-daemon's clone over the mesh only ever ran natively.
RUN apk add --no-cache git ncurses-libs libstdc++ libgcc openssl ca-certificates curl
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/mcl_git ./

ENV HOME=/app
# git finds its remote helper on PATH: `git clone mesh://...' works in the image.
ENV PATH="/app/bin:${PATH}"
ENV RELX_REPLACE_OS_VARS=true

# The boot claim's labels on the realm's Providers desk. MCL_BOX is the host
# that runs it, set where it is deployed.
ENV MCL_SERVICE_NAME=mcl-git
ENV MCL_NODE_NAME=mcl_git
ENV MCL_NODE_HOST=127.0.0.1
ENV MCL_COOKIE=mcl_git
ENV MCL_HEALTH_PORT=8471
ENV MCL_DATA_DIR=/data

# The node identity, and the store with the repositories beside it. Both must
# outlive the container: see deploy/docker-compose.yml.
VOLUME ["/etc/mcl/secrets", "/data"]

EXPOSE 8471
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${MCL_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/mcl_git", "foreground"]
