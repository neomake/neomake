# Do not let mess "cd" with user-defined paths.
CDPATH=

test: testnvim testvim

VADER?=Vader!
VIM_ARGS='+$(VADER) *.vader'

testnvim: TEST_VIM:=VADER_OUTPUT_FILE=/dev/stderr nvim --headless
testnvim: tests/vader
testnvim:
	@# Use a temporary dir with Neovim (https://github.com/neovim/neovim/issues/5277).
	tmp=$(shell mktemp -d --suffix=.neomaketests); \
	cd tests && HOME=$$tmp $(TEST_VIM) -nNu vimrc -i NONE $(VIM_ARGS)
	
testvim: TEST_VIM:=vim -X
testvim: tests/vader
testvim:
	cd tests && HOME=/dev/null $(TEST_VIM) -nNu vimrc -i NONE $(VIM_ARGS)

tests/vader:
	git clone https://github.com/junegunn/vader.vim tests/vader

# Interactive tests, keep Vader open.
testinteractive: VADER:=Vader
testinteractive: testvim

testninteractive: VADER:=Vader
testninteractive: TEST_VIM:=VADER_OUTPUT_FILE=/dev/stderr nvim
testninteractive: _run_tests

# Manually invoke Vim, using the test setup.  This helps with building tests.
runvim: VIM_ARGS:=
runvim: testinteractive

runnvim: VIM_ARGS:=
runnvim: testninteractive

# Add targets for .vader files, absolute and relative.
# This can be used with `b:dispatch = ':Make %'` in Vim.
TESTS:=$(filter-out tests/_%.vader,$(wildcard tests/*.vader))
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))
_TESTS_REL_AND_ABS:=$(call uniq,$(abspath $(TESTS)) $(TESTS))
$(_TESTS_REL_AND_ABS):
	make test VIM_ARGS='+$(VADER) $(@:tests/%=%)'
.PHONY: $(_TESTS_REL_AND_ABS)

tags:
	ctags -R --langmap=vim:+.vader

# Linters, called from .travis.yml.
vint:
	vint .
vint-errors:
	vint --error .
vimlint:
	sh /tmp/vimlint/bin/vimlint.sh -l /tmp/vimlint -p /tmp/vimlparser .
vimlint-errors:
	sh /tmp/vimlint/bin/vimlint.sh -E -l /tmp/vimlint -p /tmp/vimlparser .

.PHONY: vint vint-errors vimlint vimlint-errors
.PHONY: test testnvim testvim testinteractive runvim runnvim tags _run_tests
