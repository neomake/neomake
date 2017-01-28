# Do not let mess "cd" with user-defined paths.
CDPATH:=

test:
	$(MAKE) testnvim
	$(MAKE) testvim

SHELL:=/bin/bash -o pipefail

VADER:=Vader!
VADER_OPTIONS?=
VADER_ARGS=tests/neomake.vader $(VADER_OPTIONS)
VIM_ARGS='+$(VADER) $(VADER_ARGS)'

DEFAULT_VADER_DIR:=tests/vim/plugins/vader
export TESTS_VADER_DIR:=$(firstword $(realpath $(wildcard tests/vim/plugins/vader.override)) $(DEFAULT_VADER_DIR))
$(DEFAULT_VADER_DIR):
	mkdir -p $(dir $@)
	git clone --depth=1 -b display-source-with-exceptions https://github.com/blueyed/vader.vim $@
TESTS_FUGITIVE_DIR:=tests/vim/plugins/fugitive
$(TESTS_FUGITIVE_DIR):
	mkdir -p $(dir $@)
	git clone --depth=1 https://github.com/tpope/vim-fugitive $@

DEP_PLUGINS=$(TESTS_VADER_DIR) $(TESTS_FUGITIVE_DIR)

TEST_VIMRC:=tests/vim/vimrc

# This is expected in tests.
TEST_VIM_PREFIX:=SHELL=/bin/bash

testx: export VADER_OPTIONS=-x
testx: test

testnvimx: export VADER_OPTIONS=-x
testnvimx: testnvim

# Neovim might quit after ~5s with stdin being closed.  Use --headless mode to
# work around this.
# > Vim: Error reading input, exiting...
# > Vim: Finished.
testnvim: TEST_VIM:=nvim --headless
# Neovim needs a valid HOME (https://github.com/neovim/neovim/issues/5277).
testnvim: build/neovim-test-home
testnvim: TEST_VIM_PREFIX+=HOME=build/neovim-test-home
testnvim: TEST_VIM_PREFIX+=VADER_OUTPUT_FILE=/dev/stderr
testnvim: _run_vim
	
testvim: TEST_VIM:=vim -X
testvim: TEST_VIM_PREFIX+=HOME=/dev/null
testvim: _run_vim

# Add coloring to Vader's output:
# 1. failures (includes pending) in red "(X)"
# 2. test case header in bold "(2/2)"
# 3. Neomake's debug log messages in less intense grey
# 4. non-Neomake log lines (e.g. from :Log) in bold/bright yellow.
_SED_HIGHLIGHT_ERRORS:=| contrib/highlight-log vader
# Need to close stdin to fix spurious 'sed: couldn't write X items to stdout: Resource temporarily unavailable'.
# Redirect to stderr again for Docker (where only stderr is used from).
_REDIR_STDOUT:=2>&1 </dev/null >/dev/null $(_SED_HIGHLIGHT_ERRORS) >&2
_run_vim: | build $(DEP_PLUGINS)
_run_vim:
	$(TEST_VIM_PREFIX) $(TEST_VIM) --noplugin -Nu $(TEST_VIMRC) -i NONE $(VIM_ARGS) $(_REDIR_STDOUT)

# Interactive tests, keep Vader open.
_run_interactive: VADER:=Vader
_run_interactive: _REDIR_STDOUT:=
_run_interactive: _run_vim

testvim_interactive: TEST_VIM:=vim -X
testvim_interactive: TEST_VIM_PREFIX+=HOME=/dev/null
testvim_interactive: _run_interactive

testnvim_interactive: TEST_VIM:=nvim
testnvim_interactive: TEST_VIM_PREFIX+=HOME=build/neovim-test-home
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
	make $(TEST_TARGET) VADER_ARGS='$@ $(VADER_OPTIONS)'
.PHONY: $(_TESTS_REL_AND_ABS)

tags:
	ctags -R --langmap=vim:+.vader

# Linters, called from .travis.yml.
LINT_ARGS:=./plugin ./autoload
build/vint: | build
	virtualenv $@
	$@/bin/pip install vim-vint
vint: build/vint
	build/vint/bin/vint $(LINT_ARGS)
vint-errors: build/vint
	build/vint/bin/vint --error $(LINT_ARGS)

# vimlint
build/vimlint: | build
	git clone --depth=1 https://github.com/syngan/vim-vimlint $@
build/vimlparser: | build
	git clone --depth=1 https://github.com/ynkdir/vim-vimlparser $@
vimlint: build/vimlint build/vimlparser
	build/vimlint/bin/vimlint.sh -l build/vimlint -p build/vimlparser $(LINT_ARGS)
vimlint-errors: build/vimlint build/vimlparser
	build/vimlint/bin/vimlint.sh -E -l build/vimlint -p build/vimlparser $(LINT_ARGS)

build build/neovim-test-home:
	mkdir $@
build/neovim-test-home: | build
build/vimhelplint: | build
	cd build \
	&& wget -O- https://github.com/machakann/vim-vimhelplint/archive/master.tar.gz \
	  | tar xz \
	&& mv vim-vimhelplint-master vimhelplint
vimhelplint: export VIMHELPLINT_VIM:=vim
vimhelplint: | build/vimhelplint
	contrib/vimhelplint doc/neomake.txt

# Run tests in dockerized Vims.
DOCKER_REPO:=neomake/vims-for-tests
DOCKER_TAG:=1
DOCKER_IMAGE_DIGEST=:$(DOCKER_TAG)
DOCKER_IMAGE=$(DOCKER_REPO)$(DOCKER_IMAGE_DIGEST)
DOCKER_STREAMS:=-ti
DOCKER=docker run $(DOCKER_STREAMS) --rm \
       -v $(PWD):/testplugin -v $(abspath $(TESTS_VADER_DIR)):/testplugin/tests/vim/plugins/vader $(DOCKER_IMAGE)
docker_image:
	docker build -f Dockerfile.tests -t $(DOCKER_REPO):$(DOCKER_TAG) .
docker_push:
	docker push $(DOCKER_REPO):$(DOCKER_TAG)

# docker run --rm $(DOCKER_IMAGE) sh -c 'cd /vim-build/bin && ls vim*'
DOCKER_VIMS:=vim73 vim74-trusty vim74-xenial vim8069 vim-master
_DOCKER_VIM_TARGETS:=$(addprefix docker_test-,$(DOCKER_VIMS))

docker_test_all: $(_DOCKER_VIM_TARGETS)

$(_DOCKER_VIM_TARGETS):
	$(MAKE) docker_test DOCKER_VIM=$(patsubst docker_test-%,%,$@)

docker_test: DOCKER_VIM:=vim-master
docker_test: DOCKER_STREAMS:=-a stderr
docker_test: DOCKER_MAKE_TARGET:=testvim TEST_VIM=/vim-build/bin/$(DOCKER_VIM) VIM_ARGS="$(VIM_ARGS)"
docker_test: docker_make

docker_run: $(DEP_PLUGINS)
docker_run:
	$(DOCKER) $(if $(DOCKER_RUN),$(DOCKER_RUN),bash)

docker_make: DOCKER_RUN=make -C /testplugin $(DOCKER_MAKE_TARGET)
docker_make: docker_run

docker_vimhelplint:
	$(MAKE) docker_make "DOCKER_MAKE_TARGET=vimhelplint \
	  VIMHELPLINT_VIM=/vim-build/bin/vim-master"

check:
	@:; ret=0; \
	echo '== Checking that all tests are included'; \
	for f in $(filter-out neomake.vader,$(notdir $(shell git ls-files tests/*.vader))); do \
		if ! grep -q "^Include.*: $$f" tests/neomake.vader; then \
			echo "Test not included: $$f" >&2; ret=1; \
		fi; \
	done; \
	echo '== Checking for absent Before sections in tests'; \
	if grep '^Before:' tests/*.vader; then \
	  echo "Before: should not be used in tests itself, because it overrides the global one."; \
		(( ret+=2 )); \
	fi; \
	echo '== Checking for absent :Log calls'; \
	if grep '^\s*Log\b' $(shell git ls-files tests/*.vader $(LINT_ARGS)); then \
	  echo "Found Log commands."; \
		(( ret+=4 )); \
	fi; \
	exit $$ret

.PHONY: vint vint-errors vimlint vimlint-errors
.PHONY: test testnvim testvim testnvim_interactive testvim_interactive
.PHONY: runvim runnvim tags _run_tests
