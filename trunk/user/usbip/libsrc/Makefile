CFLAGS += -fPIC -ffunction-sections -fdata-sections
CFLAGS += -I. -I../../sysfsutils
CFLAGS += -DHAVE_CONFIG_H -DUSBIDS_FILE='"/usr/share/usb.ids"'

LDFLAGS += --gc-sections -s
LDFLAGS += -L../../sysfsutils -lsysfs

OBJS = names.o usbip_host_driver.o usbip_common.o vhci_driver.o

all: libusbip.so

libusbip.so: $(OBJS)
	$(LD) $(LDFLAGS) -shared -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $^

romfs:
	$(ROMFSINST) libusbip.so /lib/libusbip.so
	$(ROMFSINST) -s libusbip.so /lib/libusbip.so.1
	$(ROMFSINST) -s libusbip.so /lib/libusbip.so.1.1.1

clean:
	rm -f *.o *.so *.a
