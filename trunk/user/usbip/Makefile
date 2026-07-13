
usbip_dir = libsrc src

all romfs:
	for i in $(usbip_dir) ; do $(MAKE) -C $$i $@ || exit $?; done

clean:
	for i in $(usbip_dir) ; do $(MAKE) -C $$i $@; done
