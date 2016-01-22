# Neomake

A plugin for asynchronous `:make` using [Neovim's](http://neovim.org/)
job-control functionality. It is inspired by the excellent vim plugins
[Syntastic](https://github.com/scrooloose/syntastic) and
[Dispatch](https://github.com/tpope/vim-dispatch).

**This plugin also works in ordinary vim, but without the asynchronous benefits.**

This is alpha quality software. The APIs haven't totally levelled out yet, and
things may break and change often until they do. That said, I'm using it daily
(but also hacking on it as it breaks). Feel free to let me know what works /
doesn't work for you!

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

Makers provided by neomake as of this writing are:

Coffeescript:
- coffeelint

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

JSON:
- jsonlint

Jsx:
- jsxhint

Python:
- pep8
- flake8
- pyflakes
- pylama
- pylint
- python

Ruby:
- mri
- jruby
- rubocop
- reek

C:
- clang
- gcc
- clang-tidy

C++:
- clang++
- g++
- clang-tidy

CSS:
- csslint
- stylelint

D:
- dmd

sh:
- shellcheck

Rust:
- rustc

Tex/Latex:
- chktex
- lacheck

Scala:
- scalac
- scalastyle

TypeScript:
- tsc

Erlang:
- erlc

Vimscript:
- vint

Puppet:
- puppet
- puppet-lint

Lua:
- luacheck

Standard ML:
- smlnj

Markdown:
- mdl

Since this list may be out of date, look in [autoload/neomake/makers](https://github.com/benekastah/neomake/tree/master/autoload/neomake/makers) for all supported makers.

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/*.vim` to see how that is
currently done.
