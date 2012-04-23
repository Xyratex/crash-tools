
phoneys         := default install uninstall all show
scripts     	:= $(wildcard *.sh)

installation    := $(scripts:%.sh=$$HOME/bin/%)

install     	: $(installation)
	$(SHELL) mk-init-crash.sh $@

uninstall       :
	rm -f $(installation)
	$(SHELL) mk-init-crash.sh $@

$$HOME/bin/%    : %.sh
	@test -f $@ -a $< -ot $@ || { \
		cp $< $@ ; chmod a+x $@ ; echo cp $< $@ ; }

all             :
	@echo nothing to do for $@ in `pwd`

show            :
	echo $(installation) $(subdirs)
	@$(do_subdir)

.PHONEY : $(phoneys)
