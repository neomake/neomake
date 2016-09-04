[![Build Status](https://travis-ci.org/neomake/neomake.svg?branch=master)](https://travis-ci.org/neomake/neomake)

# Neomake

A plugin for asynchronous `:make` using [Neovim's](http://neovim.org/)
job-control functionality. It is inspired by the excellent vim plugins
[Syntastic](https://github.com/scrooloose/syntastic) and
[Dispatch](https://github.com/tpope/vim-dispatch).

**This plugin also works in ordinary Vim, but without the asynchronous benefits.**

The minimum Neovim version supported by Neomake is `NVIM 0.0.0-alpha+201503292107` (commit `960b9108c`).
The minimum Vim version supported by Neomake is 7.4.503 (although if you don't
use `g:neomake_logfile` older versions will probably work fine as well).

## How to use (basic)

Just set your `makeprg` and `errorformat` as normal, and run:

    :Neomake!

If your makeprg can take a filename as an input, then you can run `:Neomake`
(no exclamation point) to pass the current file as the first argument.
Otherwise, it is simply invoked in vim's current directory with no arguments.

Here's an example of how to run neomake on the current file on every write:

    autocmd! BufWritePost * Neomake

The make command will be run in an asynchronous job. The results will be
populated in the window's quickfix list for `:Neomake!` and the location
list for `:Neomake` as the job runs. Run `:copen` or `:lopen` to see the
whole list.

## How to use (advanced)

Taking a page from the book of syntastic, you can configure "makers" (called
"checkers" in syntastic) for different filetypes. Here is an example
configuration:

```viml
let g:neomake_javascript_jshint_maker = {
    \ 'args': ['--verbose'],
    \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
    \ }
let g:neomake_javascript_enabled_makers = ['jshint']
```

For use with the `:Neomake` command (makers that run on an individual file), it
is critical that makers follow this naming convention:

    g:neomake_{ language }_{ makername }_maker

Where `{ language }` is replaced with the name of the language, and `{ makername
}` is replaced with the name that you want your maker to have. If your maker
does not follow this convention, neomake will not be able to see it, and you
will get an error message like `{ makername } not found`.

Explanation for the strings making up the errorformat can be found by typing
`:h errorformat` in Neovim/Vim.

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

## Plugin documentation

For more detailed documentation please refer to the
[plugin's help](https://github.com/neomake/neomake/tree/master/doc/neomake.txt)
(`:h neomake`).


## Makers provided by Neomake as of this writing are:

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
- coffeelint

CSS:
- csslint
- stylelint

D:
- dmd

Elixir:
- credo [not enabled by default]
- dogma [not enabled by default]
- elixirc

Erlang:
- erlc

fish:
- fish

Go:
- go
- golint
- go vet

Haskell:
- hlint
- ghc-mod
- hdevtools
- cabal

Java:
- javac

Javascript:
- eslint
- standard
- jscs
- jshint
- jsxhint
- flow
- xo

JSON:
- jsonlint

Jsx:
- jsxhint

Lua:
- luac
- luacheck

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
- puppet-lint

Python:
- pep8
- flake8
- pyflakes
- pylama
- pylint
- python
- [vulture](https://bitbucket.org/jendrikseipp/vulture) [not enabled by default]
- [mypy](http://mypy-lang.org/) [not enabled by default]

Ruby:
- mri
- jruby
- rubocop
- reek
- rubylint

Rust:
- rustc

Scala:
- scalac
- scalastyle

scss:
- [sass-lint](https://github.com/sasstools/sass-lint) node.js-based linter
- [scss-lint](https://github.com/brigade/scss-lint) ruby gem-based linter

sh:

- sh
- shellcheck

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

- vint
- [vimlint](https://github.com/syngan/vim-vimlint)

  It can be installed using npm:
  [node-vimlint](https://www.npmjs.com/package/vimlint).

  Or you could create a wrapper script ``vimlint`` and add it to your PATH:

  ```sh
  #!/bin/sh
  ~/Vcs/vim-vimlint/bin/vimlint.sh -l ~/Vcs/vim-vimlint -p ~/Vcs/vim-vimlparser "$@"
  ```

YAML:
- [yamllint](http://yamllint.readthedocs.org/)

Zsh:

- shellcheck (not enabled by default, current versions do not support Zsh)
- zsh

Since this list may be out of date, look at
[autoload/neomake/makers](https://github.com/benekastah/neomake/tree/master/autoload/neomake/makers)
for all supported makers.

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/**/*.vim` to see how that is
currently done.


# Contributing

This is a community driven project, and maintainers are wanted.
Please contact [@bl;eyed](https://github.com/blueyed) if you are interested.
You should have a good profile of issue triaging and PRs on this repo already.
