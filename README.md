[![Build Status](https://travis-ci.org/neomake/neomake.svg?branch=master)](https://travis-ci.org/neomake/neomake)
[![Krihelimeter](http://krihelinator.xyz/badge/neomake/neomake)](https://github.com/neomake/neomake/pulse)

# Neomake

Neomake is a plugin that asynchronously runs programs using
[Neovim]'s job-control functionality. It is intended to
replace Vim's built-in `:make` command and provides functionality similar to
plugins like [syntastic] and [dispatch.vim]. It is primarily used to run code
linters and compilers from within Vim, but can be used to run any program.

**This plugin also works in ordinary Vim, but without the asynchronous
benefits.**

## Requirements

The minimum [Neovim] version supported by Neomake is
`NVIM 0.0.0-alpha+201503292107` ([commit 960b9108c]). The minimum Vim version
supported by Neomake is 7.4.503 (although if you don't use `g:neomake_logfile`
older versions will probably work fine as well).

## Usage

### File makers

If your `makeprg` should run on the file in the current buffer (like most
linters, e.g. you would normally type `eslint myfile.js`), then you can use
`:Neomake`.

Here's an example of how to run Neomake on the current file on every write:

```viml
autocmd! BufWritePost * Neomake
```

The make command will be run in an asynchronous job. The results will be
populated in the window's quickfix list for `:Neomake!` and the location
list for `:Neomake` as the job runs. Run `:copen` or `:lopen` to see the
whole list.

If you want to run a specific maker on the file you can specify the maker's
name, e.g. `:Neomake jshint`. The maker must be defined for the filetype.

#### Configuration

Taking a page from the book of [syntastic], you can configure "makers" (called
"checkers" in [syntastic]) for different filetypes. Here is an example
configuration that is already included with this plugin:

```viml
let g:neomake_javascript_jshint_maker = {
    \ 'args': ['--verbose'],
    \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
    \ }
let g:neomake_javascript_enabled_makers = ['jshint']
```

For use with the `:Neomake` command (makers that run on an individual file), it
is critical that makers follow this naming convention:

    g:neomake_{ filetype }_{ makername }_maker

Where `{ filetype }` is replaced with the name of the filetype, and
`{ makername }` is replaced with the name that you want your maker to have. If
your maker does not follow this convention, Neomake will not be able to see
it, and you will get an error message like `{ makername } not found`.

Explanation for the strings making up the errorformat can be found by typing
`:h errorformat` in [Neovim] (or Vim).

If the string `'%:p'` shows up anywhere in the `'args'` list, it will be
`expand()`ed to the full path of the current file in place. Otherwise, the full
path to the file will be `add()`ed to the end of the list, unless the maker's
`'append_file'` option is set to 0. You can customize the program that is
called by adding an `'exe'` property which should be a string (defaults to the
name of the maker).

Once you have created your makers, run `:Neomake` as normal. Run
`:Neomake <checker-name>` to run only a single checker. Configuring a
filetype to use makers will currently cause the `makeprg` to be ignored (this
should be remedied).

Refer to the inline documentation `:h neomake.txt` for more.

### Directory makers

Directory makers (these do not require the current filename, e.g. `make` or
`grunt build`) should be set using Vim's `makeprg` and `errorformat` options.
Then run the maker using:

    :Neomake!

In constrast to `:Neomake` without the exclamation, this will execute the
defined maker in Vim's current directory, and will not pass the filename to
the maker.

If you want to run a specific maker in the current working directory you can
specify the maker's name, e.g. `:Neomake! clean`. The maker must be defined as
a directory maker, e.g., for the `clean` example:

```viml
let g:neomake_make_maker = { 'exe': 'make', 'args': ['clean'] }
```

Refer to the inline documentation `:h neomake.txt` for more.

## Plugin documentation

For more detailed documentation, especially regarding configuration, please
refer to the [plugin's help](https://github.com/neomake/neomake/tree/master/doc/neomake.txt)
(`:h neomake.txt`).

## Included makers

This list may be out of date, look at
[autoload/neomake/makers](https://github.com/neomake/neomake/tree/master/autoload/neomake/makers)
for all supported makers.

Applescript:

- osacompile

C:

- clang
- gcc
- clang-tidy
- checkpatch

C++:

- clang++
- g++
- clang-tidy

CFEngine 3:

- cf-promises

CUDA:

- nvcc

Coffeescript:

- [coffeelint](http://www.coffeelint.org/)

CSS:

- csslint
- [stylelint](http://stylelint.io/)

D:

- [dmd](https://dlang.org/dmd-linux.html)

Elixir:

- credo (not enabled by default)
- dogma (not enabled by default)
- elixirc

Erlang:

- erlc

fish:

- fish

Fortran

- gfortran
- ifort

Go:

- go
- golint
- go vet

Haskell:

- hlint
- ghc-mod
- hdevtools
- cabal
- liquid (LiquidHaskell)

Stack projects are supported.

Java:

- javac

JavaScript / ECMAScript:

- [eslint](http://eslint.org/)
- flow
- [jscs](http://jscs.info/)
- jshint
- jsxhint
- [standard](http://standardjs.com/)
- [xo](https://github.com/sindresorhus/xo)

JSON:

- [jsonlint](https://github.com/zaach/jsonlint)

JSX:

- [jsxhint](https://github.com/STRML/JSXHint)

Lua:

- luac
- [luacheck](https://github.com/mpeterv/luacheck)

Markdown:

- [markdownlint](https://github.com/igorshubovych/markdownlint-cli)
- [mdl](https://github.com/mivok/markdownlint)
- [proselint](http://proselint.com)

nix:

- nix-instantiate

Perl:

- perlcritic

Pug:

- [pug-lint](https://github.com/pugjs/pug-lint)

Puppet:

- puppet
- [puppet-lint](http://puppet-lint.com/)

Python:

- pep8
- flake8
- pyflakes
- pylama
- pylint
- python
- [vulture](https://bitbucket.org/jendrikseipp/vulture) [not enabled by default]
- [mypy](http://mypy-lang.org/) [not enabled by default]
- [py3kwarn](https://github.com/liamcurry/py3kwarn) [not enabled by default]

Ruby:

- mri
- jruby
- [rubocop](http://batsov.com/rubocop/)
- reek
- rubylint

Rust:

- rustc
- [cargo](https://github.com/rust-lang/cargo) -- This maker should be run
  explicitly using the command `:Neomake! cargo` since it is used to compile
  projects and install Rust dependencies.
- [clippy](https://github.com/Manishearth/rust-clippy) -- This maker should be
  run explicitly using the command `:Neomake! clippy`. It needs a nightly
  build of Rust, and supports
  [rustup](https://github.com/rust-lang-nursery/rustup.rs).

Scala:

- scalac
- scalastyle

scss:

- [sass-lint](https://github.com/sasstools/sass-lint) node.js-based linter
- [scss-lint](https://github.com/brigade/scss-lint) ruby gem-based linter

sh / Bash:

- sh
- [shellcheck](https://www.shellcheck.net/)

Slim:

- [slim-lint](https://github.com/sds/slim-lint)

Standard ML:

- smlnj

Stylus:

- [stylint](https://rosspatton.github.io/stylint/)

SQL:

- [sqlint](https://github.com/purcell/sqlint)

TCL:

- Nagelfar

Tex/Latex:

- chktex
- lacheck

TypeScript:

- tsc

VHDL:

- [GHDL](https://github.com/tgingold/ghdl)

Vimscript:

- [vint](https://github.com/Kuniwak/vint)
- [vimlint](https://github.com/syngan/vim-vimlint)

  It can be installed using npm:
  [node-vimlint](https://www.npmjs.com/package/vimlint).

  Or you could create a wrapper script `vimlint` and add it to your PATH:

    ```sh
    #!/bin/sh
    /vimlint/bin/vimlint.sh -l /vimlint -p ~/Vcs/vim-vimlparser "$@"
    ```

  Where `/vimlint` is where you cloned/extracted
  [vimlint](https://github.com/syngan/vim-vimlint).

YAML:

- [yamllint](http://yamllint.readthedocs.org/)

Zsh:

- [shellcheck](https://www.shellcheck.net/) (not enabled by default, current
  versions do not support Zsh)
- zsh

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/**/*.vim` to see how that is
currently done.

# Contributing

This is a community driven project, and maintainers are wanted.
Please contact [@blueyed](https://github.com/blueyed) if you are interested.
You should have a good profile of issue triaging and PRs on this repo already.

[Neovim]: http://neovim.org/
[syntastic]: https://github.com/scrooloose/syntastic
[dispatch.vim]: https://github.com/tpope/vim-dispatch
[commit 960b9108c]: https://github.com/neovim/neovim/tree/960b9108c2928b6cf0adcabdb829d06996635211
