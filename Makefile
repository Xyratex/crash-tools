
phoneys         := default install uninstall all show
subdirs         := $(shell find */* -type f -name 'Makefile' -o -name 'mk.sh' | \
	sed 's@/[^/]*$$@@')

do_subdir       = for d in $(subdirs); do cd $$d ; \
	set -x;if test -f mk.sh ; \
	then bash ./mk.sh --$@ ; \
	else $(MAKE) $@ ; \
	fi ; cd - ; done

default     	: install

install     	:
	@$(do_subdir)

uninstall       :
	@$(do_subdir)

all             :
	@$(do_subdir)

show            :
	echo subdirectories: $(subdirs)
	@$(do_subdir)

.PHONEY : $(phoneys) please

please :
	@echo please be more insistent: $(phoneys) only.
