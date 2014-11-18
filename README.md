
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

---

**PSA:** I have opened an [issue in syntastic](https://github.com/scrooloose/syntastic/issues/1253) to take what I've learned here and move it into syntastic. Go +1 that if you think it's a good idea. If they don't bite, I'll continue maintaining this project. Otherwise, I think it makes sense to use syntastic instead (once the features available here are available in syntastic).

## How to use (basic)

Just set your `makeprg` and `errorformat` as normal, and run:

```
:Neomake
```

Here's an example of how to run neomake on every write:

```
autocmd BufWritePost *.py,*.js Neomake
```

The make command will be run in an asynchronous job. The results will be
populated in the window's location list as the job runs. Run `:lopen` to see
the whole list.

## How to use (advanced)

Taking a page from the book of syntastic, you can configure "makers" (called
"checkers" in syntastic) for different filetypes. Here is an example
configuration:

```
let g:neomake_javascript_jshint_maker = {
    \ 'args': ['--verbose'],
    \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
    \ }
let g:neomake_javascript_enabled_makers = ['jshint']
```

If the string `'%:p'` shows up anywhere in the `'args'` list, it will be
`expand()`ed to the full path of the current file in place. Otherwise, the full
path to the file will be `add()`ed to the end of the list. You can customize
the program that is called by adding an `'exe'` property which should be a
string (defaults to the name of the maker).

Once you have created your makers, run `:Neomake` as normal. Run 
`:Neomake <checker-name>` to run only a single checker. Configuring a 
filetype to use makers will currently cause the `makeprg` to be ignored (this
should be remedied).

Makers provided by neomake as of this writing are:

Javascript:

- jshint

Python:

- pep8
- pyflakes
- pylint

Go:

- go
- golint

Ruby

- rubocop

Since this list may be out of date, look in [autoload/neomake/makers](https://github.com/benekastah/neomake/tree/master/autoload/neomake/makers) for all supported makers.

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/*.vim` to see how that is
currently done.
