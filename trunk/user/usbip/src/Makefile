CFLAGS += -ffunction-sections -fdata-sections -fvisibility=hidden
CFLAGS += -I. -I../libsrc -I../../sysfsutils
CFLAGS += -DHAVE_CONFIG_H -DUSBIDS_FILE='"/usr/share/usb.ids"'

LDFLAGS += -Wl,--gc-sections -s
LDFLAGS += -L../../sysfsutils -lsysfs
LDFLAGS += -L../libsrc -lusbip

usbip_OBJS := usbip.c utils.c usbip_network.c \
	 usbip_attach.c usbip_detach.c usbip_list.c \
	 usbip_bind.c usbip_unbind.c usbip_port.c

usbipd_OBJS := usbipd.c usbip_network.c

all: usbip usbipd

usbip: $(usbip_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(usbip_OBJS)

usbipd: $(usbipd_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(usbipd_OBJS)

romfs:
	$(ROMFSINST) usbipd /sbin/usbipd
	$(ROMFSINST) usbip /sbin/usbip

clean:
	rm -f *.o *.a *.
