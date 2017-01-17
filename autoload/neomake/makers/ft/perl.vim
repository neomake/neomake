" vim: ts=4 sw=4 et
function! neomake#makers#ft#perl#EnabledMakers() abort
    return ['perl', 'perlcritic']
endfunction

function! neomake#makers#ft#perl#perlcritic() abort
    return {
         \ 'args' : ['--quiet', '--nocolor', '--verbose',
         \           '\\%f:\\%l:\\%c:(\\%s) \\%m (\\%e)\\n'],
         \ 'errorformat': '%f:%l:%c:%m,'
     \}
endfunction

function! neomake#makers#ft#perl#perl() abort
    return {
         \ 'args' : ['-c', '-X', '-Mwarnings'],
         \ 'errorformat': '%E%m at %f line %l%s,%-G%f syntax OK,%-G%f had compilation errors.',
         \ 'postprocess': function('neomake#makers#ft#perl#PerlEntryProcess'),
     \}
endfunction

function! neomake#makers#ft#perl#PerlEntryProcess(entry) abort
    let extramsg = substitute(a:entry.pattern, '\^\\V', '', '')
    let extramsg = substitute(extramsg, '\\\$', '', '')
    let a:entry.text = a:entry.text . ' ' . extramsg
endfunction
