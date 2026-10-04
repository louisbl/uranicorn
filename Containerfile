FROM ghcr.io/ublue-os/akmods:main-44 AS akmods
FROM ghcr.io/ublue-os/akmods-nvidia-open:main-44 AS akmods-nvidia

FROM scratch AS ctx
COPY build.sh /build.sh
COPY packages /packages

FROM quay.io/fedora/fedora-sway-atomic:44
COPY system_files/ /
COPY cosign.pub /etc/pki/containers/uranicorn.pub
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=bind,from=akmods,src=/,dst=/tmp/akmods \
    --mount=type=bind,from=akmods-nvidia,src=/,dst=/tmp/akmods-nvidia \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    bash /ctx/build.sh && bootc container lint
