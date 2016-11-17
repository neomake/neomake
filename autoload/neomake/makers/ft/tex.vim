" vim: ts=4 sw=4 et

function! neomake#makers#ft#tex#EnabledMakers() abort
    return ['chktex', 'lacheck', 'rubberinfo', 'proselint']
endfunction

function! neomake#makers#ft#tex#chktex()
    return {
                \ 'errorformat':
                \ '%EError %n in %f line %l: %m,' .
                \ '%WWarning %n in %f line %l: %m,' .
                \ '%WMessage %n in %f line %l: %m,' .
                \ '%Z%p^,' .
                \ '%-G%.%#'
                \ }
endfunction

function! neomake#makers#ft#tex#lacheck()
    return {
                \ 'errorformat':
                \ '%-G** %f:,' .
                \ '%E"%f"\, line %l: %m'
                \ }
endfunction

function! neomake#makers#ft#tex#rubber()
    return {
                \ 'args': ['--pdf', '-f', '--warn=all'],
                \ 'errorformat':
                \ '%f:%l: %m,' .
                \ '%f: %m'
                \ }
endfunction

function! neomake#makers#ft#tex#rubberinfo()
    return {
                \ 'exe': 'rubber-info',
                \ 'errorformat':
                \ '%f:%l: %m,' .
                \ '%f:%l-%\d%\+: %m,' .
                \ '%f: %m'
                \ }
endfunction

function! neomake#makers#ft#tex#latexrun()
    return {
                \ 'args': ['--color', 'never'],
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction

function! neomake#makers#ft#tex#proselint() abort
    return neomake#makers#ft#text#proselint()
endfunction
