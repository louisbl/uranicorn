image := "ghcr.io/louisbl/uranicorn"
vm_disk := "/var/lib/libvirt/images/uranicorn.qcow2"

# List the RPMs provided by the input images
inputs:
    #!/usr/bin/bash
    for img in $(awk '/^FROM/ { print $2 }' Containerfile); do
        echo "== $img"
        ctr=$(sudo podman create "$img" true)
        sudo podman export "$ctr" | tar -t | grep '\.rpm$' || true
        sudo podman rm -f "$ctr" >/dev/null
    done

build:
    sudo podman build --pull=newer -t {{image}}:dev .

vm:
    mkdir -p output
    sudo podman run --rm -it --privileged --security-opt label=type:unconfined_t \
        -v ./output:/output -v ./vm.toml:/config.toml:ro \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 --rootfs btrfs --local {{image}}:dev
    sudo cp output/qcow2/disk.qcow2 {{vm_disk}}
    sudo virt-install --name uranicorn-test --vcpus 4 --memory 6144 --import \
        --disk {{vm_disk}} --os-variant fedora-unknown \
        --boot uefi \
        --video model.type=virtio,model.acceleration.accel3d=yes \
        --graphics spice,listen=none,gl.enable=yes,gl.rendernode=/dev/dri/by-path/pci-0000:00:02.0-render \
       --noautoconsole

verify:
    cosign verify --key cosign.pub {{image}}:latest
