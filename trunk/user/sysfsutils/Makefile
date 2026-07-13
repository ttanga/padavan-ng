CFLAGS += -fPIC -ffunction-sections -fdata-sections
CFLAGS += -Ilib -Isysfs
LDFLAGS += --gc-sections -s

OBJS = lib/sysfs_utils.o lib/sysfs_attr.o lib/sysfs_class.o lib/dlist.o \
	lib/sysfs_device.o lib/sysfs_driver.o lib/sysfs_bus.o lib/sysfs_module.o

all: libsysfs.so

libsysfs.so: $(OBJS)
	$(LD) $(LDFLAGS) -shared -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $^

romfs:
	$(ROMFSINST) libsysfs.so /lib/libsysfs.so
	$(ROMFSINST) -s libsysfs.so /lib/libsysfs.so.2
	$(ROMFSINST) -s libsysfs.so /lib/libsysfs.so.2.1.0

clean:
	rm -rf *.o *a *.so
