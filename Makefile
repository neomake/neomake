# Do not let mess "cd" with user-defined paths.
CDPATH:=

test: testnvim testvim

# This is expected in tests.
export SHELL:=/bin/bash

VADER:=Vader!
VADER_ARGS:=tests/neomake.vader
VIM_ARGS='+$(VADER) $(VADER_ARGS)'

DEFAULT_VADER_DIR:=tests/vim/plugins/vader
export TESTS_VADER_DIR:=$(abspath $(firstword $(wildcard tests/vim/plugins/vader.override) $(DEFAULT_VADER_DIR)))
$(TESTS_VADER_DIR) $(DEFAULT_VADER_DIR):
	mkdir -p $(dir $@)
	git clone --depth=1 https://github.com/junegunn/vader.vim $@

TEST_VIMRC:=tests/vim/vimrc

TEST_VIM_PREFIX:=

testnvim: TEST_VIM:=nvim
# Neovim needs a valid HOME (https://github.com/neovim/neovim/issues/5277).
testnvim: build/neovim-test-home
testnvim: TEST_VIM_PREFIX+=HOME=build/neovim-test-home
testnvim: TEST_VIM_PREFIX+=VADER_OUTPUT_FILE=/dev/stderr
testnvim: _run_vim
	
testvim: TEST_VIM:=vim -X
testvim: TEST_VIM_PREFIX+=HOME=/dev/null
testvim: _run_vim

_REDIR_STDOUT:=>/dev/null
_run_vim: | build $(TESTS_VADER_DIR)
_run_vim:
	$(TEST_VIM_PREFIX) $(TEST_VIM) -u $(TEST_VIMRC) -i NONE $(VIM_ARGS) $(_REDIR_STDOUT)

# Interactive tests, keep Vader open.
_run_interactive: VADER:=Vader
_run_interactive: _REDIR_STDOUT:=
_run_interactive: _run_vim

testvim_interactive: TEST_VIM:=vim -X
testvim_interactive: _run_interactive

testnvim_interactive: TEST_VIM:=nvim
testnvim_interactive: _run_interactive


# Manually invoke Vim, using the test setup.  This helps with building tests.
runvim: VIM_ARGS:=
runvim: testvim_interactive

runnvim: VIM_ARGS:=
runnvim: testnvim_interactive

TEST_TARGET:=test

# Add targets for .vader files, absolute and relative.
# This can be used with `b:dispatch = ':Make %'` in Vim.
TESTS:=$(wildcard tests/*.vader tests/*/*.vader)
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))
_TESTS_REL_AND_ABS:=$(call uniq,$(abspath $(TESTS)) $(TESTS))
$(_TESTS_REL_AND_ABS):
	make $(TEST_TARGET) VADER_ARGS='$@'
.PHONY: $(_TESTS_REL_AND_ABS)

tags:
	ctags -R --langmap=vim:+.vader

# Linters, called from .travis.yml.
LINT_FILES:=./plugin ./autoload
build/vint: | build
	virtualenv $@
	$@/bin/pip install vim-vint
vint: build/vint
	build/vint/bin/vint $(LINT_FILES)
vint-errors: build/vint
	build/vint/bin/vint --error $(LINT_FILES)

# vimlint
build/vimlint: | build
	git clone --depth=1 https://github.com/syngan/vim-vimlint $@
build/vimlparser: | build
	git clone --depth=1 https://github.com/ynkdir/vim-vimlparser $@
vimlint: build/vimlint build/vimlparser
	build/vimlint/bin/vimlint.sh -l build/vimlint -p build/vimlparser $(LINT_FILES)
vimlint-errors: build/vimlint build/vimlparser
	build/vimlint/bin/vimlint.sh -E -l build/vimlint -p build/vimlparser $(LINT_FILES)

build build/neovim-test-home:
	mkdir $@
build/neovim-test-home: | build
build/vim-vimhelplint-master: | build
	cd build \
	&& wget -O- https://github.com/machakann/vim-vimhelplint/archive/master.tar.gz \
	  | tar xz
vimhelplint: VIMHELPLINT_VIM:=vim
vimhelplint: | build/vim-vimhelplint-master
	out="$$($(VIMHELPLINT_VIM) -esN -c 'e doc/neomake.txt' -c 'set ft=help' \
	  -c 'source build/vim-vimhelplint-master/ftplugin/help_lint.vim' \
	  -c 'verb VimhelpLintEcho' -c q 2>&1)"; \
	  if [ -n "$$out" ]; then \
	    echo "$$out"; \
	    exit 1; \
	  fi

docker_vimhelplint:
	$(MAKE) docker_make "DOCKER_MAKE_TARGET=vimhelplint \
	  VIMHELPLINT_VIM=/vim-build/bin/vim-master"

docker_make: DOCKER_RUN=make -C /testplugin $(DOCKER_MAKE_TARGET)
docker_make: docker_run

# Run tests in dockerized Vims.
DOCKER_IMAGE:=neomake/vims-for-tests
DOCKER_STREAMS:=-ti
DOCKER=docker run $(DOCKER_STREAMS) --rm \
       -v $(PWD):/testplugin -v $(PWD)/tests/vim:/home $(DOCKER_IMAGE)
docker_image:
	docker build -f Dockerfile.tests -t $(DOCKER_IMAGE) .
docker_push:
	docker push $(DOCKER_IMAGE)

DOCKER_VIMS:=vim73 vim74-trusty vim74-xenial vim8000 vim8069 vim-master
_DOCKER_VIM_TARGETS:=$(addprefix docker_test-,$(DOCKER_VIMS))

docker_test_all: $(_DOCKER_VIM_TARGETS)

$(_DOCKER_VIM_TARGETS):
	$(MAKE) docker_test DOCKER_VIM=$(patsubst docker_test-%,%,$@)

docker_test: DOCKER_VIM:=vim-master
docker_test: DOCKER_STREAMS:=-a stderr
docker_test: DOCKER_MAKE_TARGET:=testvim TEST_VIM=/vim-build/bin/$(DOCKER_VIM) VIM_ARGS="$(VIM_ARGS)"
docker_test: docker_make

docker_run: TESTS_VADER_DIR:=$(DEFAULT_VADER_DIR)
docker_run: $(DEFAULT_VADER_DIR)
docker_run:
	$(DOCKER) $(if $(DOCKER_RUN),$(DOCKER_RUN),bash)

.PHONY: vint vint-errors vimlint vimlint-errors
.PHONY: test testnvim testvim testnvim_interactive testvim_interactive
.PHONY: runvim runnvim tags _run_tests
