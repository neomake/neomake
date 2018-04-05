
function! neomake#makers#ft#erlang#EnabledMakers() abort
    return ['rebar3_erlc']
endfunction

function! neomake#makers#ft#erlang#erlc() abort
    return {
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

if !exists("g:rebar3_command")
    let g:rebar3_command = "rebar3"
endif

function! neomake#makers#ft#erlang#rebar3_erlc() abort
    let l:ebins = systemlist(g:rebar3_command . " path")
    let l:args = []
    for ebin in ebins
        call add(l:args, '-pa')
        call add(l:args, ebin)
        call add(l:args, '-I')
        call add(l:args, substitute(ebin, "ebin$", "include", ""))
    endfor
    call add(l:args, '-o')
    call add(l:args, '_build/neomake')
    return {
        \ 'exe': 'erlc',
        \ 'args': l:args,
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction
