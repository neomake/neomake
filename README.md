
# Neomake

A plugin for asynchronous `:make` using [Neovim's](http://neovim.org/)
job-control functionality. It is inspired by the excellent vim plugins
[Syntastic](https://github.com/scrooloose/syntastic) and
[Dispatch](https://github.com/tpope/vim-dispatch).

## How to use (basic)

Just set your `makeprg` and `errorformat` as normal, and run:

```
:Neomake
```

Here's an example of how to run neomake on every write:

```
if has('nvim')
    autocmd BufWritePost *.py,*.js NeomakeFile
endif
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

Makers currently provided by neomake are:

Javascript:

- jshint

Python:

- pep8
- pyflakes
- pylint

If you find this plugin useful, please contribute your maker recipes to the
repository! Check out `autoload/neomake/makers/*.vim` to see how that is
currently done.

## Issues

- Currently neomake add a sign for every item added to the location list. Any
  signs already at a loclist location will be removed before neomake adds one.
  This feature and it's destructive nature should probably be controlled by
  settings.
- The signs symbols should be configurable and should match the background of
  the sign area. Not sure how to do the background part myself.
- Since makers operate on the current buffer and makeprgs potentially operate 
  on the whole project, there should be a way to use both. Currently configuring 
  makers for a filetype will cause neomake to ignore the makeprg.
