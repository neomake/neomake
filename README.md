# [![Neomake](https://cloud.githubusercontent.com/assets/111942/22717189/9e3e1760-ed67-11e6-94c5-e8955869d6d0.png)](#neomake)

[![Build Status](https://travis-ci.org/neomake/neomake.svg?branch=master)](https://travis-ci.org/neomake/neomake)

Neomake is a plugin that asynchronously runs programs using
[Neovim]'s or [Vim]'s job-control functionality. It is intended to
replace the built-in `:make` command and provides functionality similar to
plugins like [syntastic] and [dispatch.vim]. It is primarily used to run code
linters and compilers from within Vim, but can be used to run any program.

## Requirements

The minimum [Neovim] version supported by Neomake is
`NVIM 0.0.0-alpha+201503292107` ([commit 960b9108c]). The minimum Vim version
supported by Neomake is 7.4.503 (although if you don't use `g:neomake_logfile`
older versions will probably work fine as well).

Vim's async mode is used with Vim 8.0.0027 or later.

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
`:h errorformat` in Vim.

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

Also commonly referred to as "Project makers", though they technically run
from the current working directory only since Vim does not know what
a "project" is.

Directory makers (these do not require the current filename, e.g. `make` or
`grunt build`) should be set using Vim's `makeprg` and `errorformat` options.
Then run the maker using:

    :Neomake!

In constrast to `:Neomake` (without the exclamation mark), this will execute the
defined maker in Vim's current directory, and will not pass the filename to
the maker.

If you want to run a specific maker in the current working directory you can
specify the maker's name, e.g. `:Neomake! makeclean`. The maker must be
defined as a directory maker, e.g., for the `makeclean` example:

```viml
let g:neomake_makeclean_maker = { 'exe': 'make', 'args': ['clean'] }
```

An example of a directory maker is the [cargo] for Rust, which you should run
as `:Neomake! cargo`. This runs `cargo`, which both installs dependencies (like
PHP's composer or Node.js's NVM) and compiles the project by calling `rustc`.

Another example is [mvn], which is the maker name for Apache Maven, a Java
project management tool. If you're working on a Java file that is part of a
Maven project, you can use the command `:Neomake! mvn` to run the
`mvn install` command using Neomake.

Refer to the inline documentation `:h neomake.txt` for more.

## Plugin documentation

For more detailed documentation, especially regarding configuration, please
refer to the [plugin's help](https://github.com/neomake/neomake/tree/master/doc/neomake.txt)
(`:h neomake.txt`).

For supplemental information on makers, check out the
[Makers page in the wiki](https://github.com/neomake/neomake/wiki/Makers)

# Contributing

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/**/*.vim` to see how that is
currently done.

This is a community driven project, and maintainers are wanted.
Please contact [@blueyed](https://github.com/blueyed) if you are interested.
You should have a good profile of issue triaging and PRs on this repo already.

## Hacking / Testing

We are using [Vader](https://github.com/junegunn/vader.vim) for our tests, and
they get run for every pull request in different environments (via Docker
also).

### Running tests

#### Run all tests against your local Neovim and Vim

    make test

#### Run a specific test file

    make tests/integration.vader

#### Run some specific tests for Vim

    make testvim VADER_ARGS=tests/integration.vader

### Dockerized tests

The `docker_test` target provides running tests for a specific Vim version.
See `Dockerfile.tests` for the Vim versions provided in the Docker image.

The image for this gets pulled from Docker Hub via
[neomake/vims-for-tests](https://hub.docker.com/r/neomake/vims-for-tests/).

NOTE: the Docker image used for tests does not include (different versions)
of Neovim at the moment.

#### Run all tests for Vim 8.0.0069

    make docker_test DOCKER_VIM=vim8069

#### Run all tests against all Vims in the Docker image

    make docker_test_all

## Donate

 * Bitcoin: 1JscK5VaHyBhdE2ayVr63hDc6Mx94m9Y7R
 * Flattr: [![Flattr](http://api.flattr.com/button/flattr-badge-large.png)](
https://flattr.com/submit/auto?user_id=blueyed&url=https://github.com/neomake/neomake&title=Neomake&language=en_GB&tags=github&category=software)


[Neovim]: http://neovim.org/
[Vim]: http://vim.org/
[syntastic]: https://github.com/scrooloose/syntastic
[dispatch.vim]: https://github.com/tpope/vim-dispatch
[commit 960b9108c]: https://github.com/neovim/neovim/tree/960b9108c2928b6cf0adcabdb829d06996635211
[cargo]: https://github.com/neomake/neomake/blob/master/autoload/neomake/makers/cargo.vim
[mvn]: https://github.com/neomake/neomake/blob/master/autoload/neomake/makers/mvn.vim
