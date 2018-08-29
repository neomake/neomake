" vim: ts=4 sw=4 et

function! Check_build_folder(opts, ) abort dict

  " todo check for nix-shell
  if isdirectory("build")
    let self.cwd = getcwd().'/build'
  endif

  if !exists("$IN_NIX_SHELL")
    echom "You are not in a nix-shell" 
  endif

  return self
endfunction

function! neomake#makers#nix#nix() abort
    \ 'exe': expand("%:p:h").'/nix-shell-maker.sh',
    \ 'args': [],
    \ 'errorformat': '%f:%l:%c: %m',
    \ 'remove_invalid_entries': 0,
    \ 'buffer_output': 0,
    \ 'InitForJob': function('Check_build_folder')
    \ }
endfunc

