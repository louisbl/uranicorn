image := "localhost/uranicorn:dev"
vm := "uranicorn-test"
host := if path_exists("/run/.toolboxenv") == "true" { "flatpak-spawn --host " } else { "" }

# List the RPMs provided by the input images
inputs:
    #!/usr/bin/bash
    for img in $(awk '/^FROM/ { print $2 }' Containerfile); do
        echo "== $img"
        ctr=$(podman create "$img" true)
        podman export "$ctr" | tar -t | grep '\.rpm$' || true
        podman rm -f "$ctr" >/dev/null
    done

lint:
    shellcheck -S warning build.sh
    for f in packages/*.txt; do LC_ALL=C sort -cu "$f"; done

sort:
    for f in packages/*.txt; do LC_ALL=C sort -u -o "$f" "$f"; done

build:
    podman build --pull=newer -t {{image}} .

check: build
    {{host}}bcvk ephemeral run-ssh {{image}} 'systemctl --failed --no-legend; cat /proc/cmdline; readlink /etc/systemd/system/display-manager.service'

vm: build
    {{host}}bcvk libvirt run --filesystem btrfs --name {{vm}} --memory 6144 --cpus 4 {{image}}

vm-ssh:
    {{host}}bcvk libvirt ssh {{vm}}

vm-rm:
    {{host}}bcvk libvirt rm -f {{vm}}

verify:
    cosign verify --key cosign.pub ghcr.io/louisbl/uranicorn:latest

