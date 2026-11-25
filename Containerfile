ARG ASHELL_VERSION=0.12.1

FROM ghcr.io/ublue-os/akmods:main-45 AS akmods
FROM ghcr.io/ublue-os/akmods-nvidia-open:main-45 AS akmods-nvidia

FROM quay.io/fedora/fedora:45 AS ashell-builder
ARG ASHELL_VERSION
RUN dnf -y install rust cargo git pkgconf-pkg-config \
        fontconfig-devel systemd-devel pipewire-devel clang-devel \
    && dnf clean all
RUN git clone --depth 1 --branch "${ASHELL_VERSION}" \
        https://github.com/MalpenZibo/ashell /build/ashell
RUN --mount=type=cache,dst=/root/.cargo/registry \
    --mount=type=cache,dst=/root/.cargo/git \
    --mount=type=cache,dst=/build/target \
    CARGO_TARGET_DIR=/build/target cargo build --locked --release \
        --manifest-path /build/ashell/Cargo.toml \
    && cp /build/target/release/ashell /usr/local/bin/ashell

FROM scratch AS ctx
COPY build.sh /build.sh
COPY packages /packages

FROM quay.io/fedora/fedora-sway-atomic:45
COPY system_files/ /
COPY --from=ashell-builder /usr/local/bin/ashell /usr/bin/ashell
COPY cosign.pub /etc/pki/containers/uranicorn.pub
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=bind,from=akmods,src=/,dst=/tmp/akmods \
    --mount=type=bind,from=akmods-nvidia,src=/,dst=/tmp/akmods-nvidia \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    bash /ctx/build.sh && bootc container lint
