" vim: ts=4 sw=4 et
function! neomake#makers#ft#vim#EnabledMakers()
    return ['perlcritic' ]
endfunction

function! neomake#makers#ft#perl#perlcritic() abort
    return { 
         \ 'args' : ['--quiet', '--nocolor', '--verbose', '\\%f:\\%l:\\%c:(\\%s) \\%m (\\%e)\\n'],
         \ 'errorformat': 
         \ '%f:%l:%c:%m,'
     \}
endfunction
