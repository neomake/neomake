" vim: ts=4 sw=4 et
function! neomake#makers#ft#perl#EnabledMakers()
    return ['perl', 'perlcritic']
endfunction

function! neomake#makers#ft#perl#perlcritic() abort
    return { 
         \ 'args' : ['--quiet', '--nocolor', '--verbose', '\\%f:\\%l:\\%c:(\\%s) \\%m (\\%e)\\n'],
         \ 'errorformat': 
         \ '%f:%l:%c:%m,'
     \}
endfunction

function! neomake#makers#ft#perl#perl() abort
    return { 
         \ 'args' : ['-c', "-X", "-Mwarnings"],
         \ 'errorformat': '%m at %f line %l%s',
         \ 'buffer_output': 1
     \}
endfunction
