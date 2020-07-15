" Test for different error types.
" Can be called using `vim -u ...`, or `:source %`.
"
" E: error
" W: warning
" I: info
" M: message
" S: style
" ?: no-type

let s:plugin_dir = expand('<sfile>:p:h:h:h')
let &runtimepath = s:plugin_dir . ',' . &runtimepath
let s:sfile = expand('<sfile>')
set noloadplugins
if &compatible
  let &compatible = 0
endif
exe 'source '.fnameescape(s:plugin_dir.'/plugin/neomake.vim')

" Use some specific colorscheme.
" let &runtimepath = expand('<sfile>:p:h') . '/colorscheme-colorish,' . &runtimepath
" set termguicolors
" colorscheme onedarkish

let s:maker = {}
function! s:maker.get_list_entries(...) abort
  let entries = [
        \ {'lnum': 4, 'type': 'E', 'text': 'error'},
        \ {'lnum': 5, 'type': 'W', 'text': 'warning'},
        \ {'lnum': 6, 'type': 'I', 'text': 'info'},
        \ {'lnum': 7, 'type': 'M', 'text': 'message'},
        \ {'lnum': 8, 'type': 'S', 'text': 'style'},
        \ {'lnum': 9, 'type': '',  'text': 'no-type'},
        \ ]
  let bufnr = bufnr('%')
  call map(entries, 'extend(v:val, {''bufnr'': bufnr})')
  return entries
endfunction

if has('vim_starting')
  " For `-u`.
  function! s:VimEnter() abort
    filetype plugin indent on
    syntax on

    exe 'edit '.s:sfile
    call neomake#Make(1, [s:maker])
  endfunction
  augroup test
    au VimEnter * ++nested call s:VimEnter()
  augroup END
else
  " For manual setup: `:source %`.
  call neomake#Make(1, [s:maker])
endif

" vim: set et sw=2
