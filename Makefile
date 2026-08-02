# Install the executables in local-bin/ into the user's private bin directory.
#
# $HOME/.local/bin is the default because that is where claude/settings.json
# expects to find them: every hook there invokes
# $HOME/.local/bin/claude-tmux-state.
#
#   make install              install into ~/.local/bin
#   make install PREFIX=/usr  install into /usr/bin
#   make uninstall            remove the installed copies
#   make check                syntax-check the scripts before installing

PREFIX  ?= $(HOME)/.local
BINDIR  ?= $(PREFIX)/bin
DESTDIR ?=

INSTALL ?= install
MODE    ?= 755

# Discovered rather than listed, so a new script in local-bin/ is installed
# without editing this file. Non-executable files (notes, data) are skipped:
# the executable bit in git is what marks something as a command.
SOURCES := $(shell find local-bin -maxdepth 1 -type f -perm -u+x | sort)
NAMES   := $(notdir $(SOURCES))
TARGETS := $(addprefix $(DESTDIR)$(BINDIR)/,$(NAMES))

.PHONY: help install uninstall check list

help:
	@echo 'Targets:'
	@echo '  install    Install local-bin executables into $(BINDIR)'
	@echo '  uninstall  Remove them from $(BINDIR)'
	@echo '  check      Syntax-check the scripts'
	@echo '  list       Show what install would copy'
	@echo
	@echo 'Override the destination with PREFIX, BINDIR, or DESTDIR:'
	@echo '  make install BINDIR=$$HOME/bin'

# Each script is its own target, so an unchanged script is not recopied and
# "make install" reports only what it actually did.
$(DESTDIR)$(BINDIR)/%: local-bin/%
	@mkdir -p $(dir $@)
	$(INSTALL) -m $(MODE) $< $@

install: $(TARGETS)
	@case ":$$PATH:" in \
	    *":$(BINDIR):"*) ;; \
	    *) echo; \
	       echo "Note: $(BINDIR) is not in PATH; add it to your shell profile."; \
	       echo '  export PATH="$(BINDIR):$$PATH"' ;; \
	esac

uninstall:
	rm -f $(TARGETS)

list:
	@echo 'Installing into $(DESTDIR)$(BINDIR):'
	@for name in $(NAMES); do echo "  $$name"; done

# Parse-only check: catches syntax errors before a broken script is copied
# over a working one. The interpreter comes from the shebang so that the
# /bin/sh scripts are not checked as bash.
check:
	@status=0; \
	for src in $(SOURCES); do \
	    shell=$$(sed -n '1s|^#!.*[ /]\([a-z]*sh\)$$|\1|p' "$$src"); \
	    [ -n "$$shell" ] || shell=sh; \
	    if $$shell -n "$$src"; then \
	        echo "ok    $$src"; \
	    else \
	        echo "FAIL  $$src"; \
	        status=1; \
	    fi; \
	done; \
	exit $$status
