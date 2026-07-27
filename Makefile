.PHONY: build-iso write-usb test-vm boot-vm lint

OUTPUT_ISO := output/ubuntu-autoinstall.iso
TEST_VM_DISK_SIZE := 40G

build-iso:
	./scripts/build-iso.sh

write-usb:
ifndef DEVICE
	$(error Usage: make write-usb DEVICE=/dev/sdX)
endif
	@echo "ATTENTION : ceci va EFFACER TOUT le contenu de $(DEVICE)."
	@read -p "Tapez 'oui' pour confirmer : " confirm && [ "$$confirm" = "oui" ]
	sudo dd if=$(OUTPUT_ISO) of=$(DEVICE) bs=4M status=progress conv=fsync
	sync

test-vm:
	@test -f output/test-vm-disk.qcow2 || qemu-img create -f qcow2 output/test-vm-disk.qcow2 $(TEST_VM_DISK_SIZE)
	qemu-system-x86_64 \
		-enable-kvm \
		-m 4096 \
		-smp 2 \
		-cdrom $(OUTPUT_ISO) \
		-drive file=output/test-vm-disk.qcow2,if=virtio,format=qcow2 \
		-boot once=d

boot-vm:
	@test -f output/test-vm-disk.qcow2 || { echo "Aucun disque de test (output/test-vm-disk.qcow2) : lancez d'abord make test-vm" >&2; exit 1; }
	qemu-system-x86_64 \
		-enable-kvm \
		-m 4096 \
		-smp 2 \
		-drive file=output/test-vm-disk.qcow2,if=virtio,format=qcow2 \
		-netdev user,id=net0 \
		-device virtio-net-pci,netdev=net0

lint:
	yamllint .
	ansible-lint ansible/
