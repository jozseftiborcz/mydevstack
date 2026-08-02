# Install the executables in local-bin/ into the user's private bin directory,
# together with the shell completions in completions/.
#
# $HOME/.local/bin is the default because that is where claude/settings.json
# expects to find them: every hook there invokes
# $HOME/.local/bin/claude-tmux-state.
#
#   make install              install into ~/.local/bin (+ completions)
#   make install PREFIX=/usr  install into /usr/bin
#   make install YES=1        install without being asked about the rc files
#   make install SKIP_RC=1    install without touching the rc files at all
#   make uninstall            remove the installed copies
#   make check                syntax-check the scripts before installing
#
# Installing asks before adding the block that loads the completions to
# ~/.bashrc and ~/.zshrc; declining just prints the lines instead.

PREFIX  ?= $(HOME)/.local
BINDIR  ?= $(PREFIX)/bin
DESTDIR ?=

# The defaults are the directories bash-completion and zsh search under a
# user's data home, so no extra configuration is needed for bash.
BASHCOMPDIR ?= $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR  ?= $(PREFIX)/share/zsh/site-functions

INSTALL   ?= install
MODE      ?= 755
DATA_MODE ?= 644

# YES=1 answers the rc-file question up front, SKIP_RC=1 leaves the rc files
# alone. Both are empty by default, so an interactive install asks.
YES     ?=
SKIP_RC ?=
RC_TOOL := tools/completion-rc

# Discovered rather than listed, so a new script in local-bin/ is installed
# without editing this file. Non-executable files (notes, data) are skipped:
# the executable bit in git is what marks something as a command.
SOURCES := $(shell find local-bin -maxdepth 1 -type f -perm -u+x | sort)
NAMES   := $(notdir $(SOURCES))
TARGETS := $(addprefix $(DESTDIR)$(BINDIR)/,$(NAMES))

# Completions are named after the command they complete: bash sources the file
# matching the command name, zsh autoloads "_command" from $fpath.
BASH_SOURCES := $(sort $(wildcard completions/bash/*))
ZSH_SOURCES  := $(sort $(wildcard completions/zsh/_*))
BASH_TARGETS := $(addprefix $(DESTDIR)$(BASHCOMPDIR)/,$(notdir $(BASH_SOURCES)))
ZSH_TARGETS  := $(addprefix $(DESTDIR)$(ZSHCOMPDIR)/,$(notdir $(ZSH_SOURCES)))
COMP_TARGETS := $(BASH_TARGETS) $(ZSH_TARGETS)

# Helpers that run from the checkout and are never installed.
TOOL_SOURCES := $(sort $(wildcard tools/*))

.PHONY: help install install-bin install-completions install-rc \
        uninstall uninstall-rc check list

help:
	@echo 'Targets:'
	@echo '  install              Install everything below'
	@echo '  install-bin          Install local-bin executables into $(BINDIR)'
	@echo '  install-completions  Install bash and zsh completions'
	@echo '  install-rc           Ask to load the completions from the rc files'
	@echo '  uninstall            Remove the installed copies and the rc block'
	@echo '  check                Syntax-check the scripts and completions'
	@echo '  list                 Show what install would copy'
	@echo
	@echo 'Override the destination with PREFIX, BINDIR, DESTDIR,'
	@echo 'BASHCOMPDIR, or ZSHCOMPDIR:'
	@echo '  make install BINDIR=$$HOME/bin'
	@echo
	@echo 'YES=1 answers the rc-file question, SKIP_RC=1 skips it:'
	@echo '  make install YES=1'

# Each file is its own target, so an unchanged one is not recopied and
# "make install" reports only what it actually did.
$(DESTDIR)$(BINDIR)/%: local-bin/%
	@mkdir -p $(dir $@)
	$(INSTALL) -m $(MODE) $< $@

$(DESTDIR)$(BASHCOMPDIR)/%: completions/bash/%
	@mkdir -p $(dir $@)
	$(INSTALL) -m $(DATA_MODE) $< $@

$(DESTDIR)$(ZSHCOMPDIR)/_%: completions/zsh/_%
	@mkdir -p $(dir $@)
	$(INSTALL) -m $(DATA_MODE) $< $@

install: install-bin install-completions install-rc

install-bin: $(TARGETS)
	@case ":$$PATH:" in \
	    *":$(BINDIR):"*) ;; \
	    *) echo; \
	       echo "Note: $(BINDIR) is not in PATH; add it to your shell profile."; \
	       echo '  export PATH="$(BINDIR):$$PATH"' ;; \
	esac

install-completions: $(COMP_TARGETS)

# Neither shell picks a private completion directory up on its own: zsh only
# autoloads from $fpath, and bash's dynamic loading needs bash-completion to
# be active. The rc block covers both, so it is offered here rather than
# leaving the installed files inert. A staged install (DESTDIR) belongs to a
# package manager, so the rc files are left alone there.
install-rc: install-completions
	@if [ -n "$(DESTDIR)" ]; then \
	    echo "Skipping the rc files: DESTDIR is set."; \
	elif [ -n "$(SKIP_RC)" ]; then \
	    echo "Skipping the rc files: SKIP_RC is set."; \
	else \
	    $(RC_TOOL) install \
	        --bash-dir '$(BASHCOMPDIR)' \
	        --zsh-dir '$(ZSHCOMPDIR)' \
	        $(if $(YES),--yes); \
	fi

uninstall: uninstall-rc
	rm -f $(TARGETS) $(COMP_TARGETS)

# Removing the files without removing the block would leave both rc files
# pointing at completions that are no longer there.
uninstall-rc:
	@if [ -n "$(DESTDIR)" ] || [ -n "$(SKIP_RC)" ]; then \
	    exit 0; \
	fi; \
	$(RC_TOOL) uninstall $(if $(YES),--yes)

list:
	@echo 'Installing into $(DESTDIR)$(BINDIR):'
	@for name in $(NAMES); do echo "  $$name"; done
	@echo 'Installing into $(DESTDIR)$(BASHCOMPDIR):'
	@for name in $(notdir $(BASH_SOURCES)); do echo "  $$name"; done
	@echo 'Installing into $(DESTDIR)$(ZSHCOMPDIR):'
	@for name in $(notdir $(ZSH_SOURCES)); do echo "  $$name"; done

# Parse-only check: catches syntax errors before a broken script is copied
# over a working one. The interpreter comes from the shebang so that the
# /bin/sh scripts are not checked as bash. The zsh completions start with
# "#compdef" rather than a shebang and are skipped when zsh is not installed.
check:
	@status=0; \
	for src in $(SOURCES) $(TOOL_SOURCES) $(BASH_SOURCES); do \
	    shell=$$(sed -n '1s|^#!.*[ /]\([a-z]*sh\)$$|\1|p' "$$src"); \
	    [ -n "$$shell" ] || shell=sh; \
	    if $$shell -n "$$src"; then \
	        echo "ok    $$src"; \
	    else \
	        echo "FAIL  $$src"; \
	        status=1; \
	    fi; \
	done; \
	if command -v zsh >/dev/null 2>&1; then \
	    for src in $(ZSH_SOURCES); do \
	        if zsh -n "$$src"; then \
	            echo "ok    $$src"; \
	        else \
	            echo "FAIL  $$src"; \
	            status=1; \
	        fi; \
	    done; \
	else \
	    for src in $(ZSH_SOURCES); do echo "skip  $$src (zsh not installed)"; done; \
	fi; \
	exit $$status
