.PHONY: build-iso write-usb test-vm lint

OUTPUT_ISO := output/ubuntu-autoinstall.iso

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
	@test -f output/test-vm-disk.qcow2 || qemu-img create -f qcow2 output/test-vm-disk.qcow2 20G
	qemu-system-x86_64 \
		-enable-kvm \
		-m 4096 \
		-smp 2 \
		-cdrom $(OUTPUT_ISO) \
		-drive file=output/test-vm-disk.qcow2,if=virtio,format=qcow2 \
		-boot once=d

lint:
	yamllint .
	ansible-lint ansible/
