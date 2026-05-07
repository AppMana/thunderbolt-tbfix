KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all clean

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/thunderbolt modules
	$(MAKE) -C $(KDIR) M=$(CURDIR)/thunderbolt_net \
		KBUILD_EXTRA_SYMBOLS=$(CURDIR)/thunderbolt/Module.symvers modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/thunderbolt clean
	$(MAKE) -C $(KDIR) M=$(CURDIR)/thunderbolt_net clean
