" vim: ts=4 sw=4 et

function! neomake#makers#ft#elixir#PostprocessEnforceMaxBufferLine(entry) abort
    let buffer_lines = str2nr(line('$'))
    if (buffer_lines < a:entry.lnum)
        let a:entry.lnum = buffer_lines
    endif
endfunction

function! neomake#makers#ft#elixir#PostprocessCredoErrorType(entry) abort
    if a:entry.type ==# 'F'      " Refactoring opportunities
        let type = 'W'
    elseif a:entry.type ==# 'D'  " Software design suggestions
        let type = 'I'
    elseif a:entry.type ==# 'W'  " Warnings
        let type = 'W'
    elseif a:entry.type ==# 'R'  " Readability suggestions
        let type = 'I'
    elseif a:entry.type ==# 'C'  " Convention violation
        let type = 'W'
    else
        let type = 'M'           " Everything else is a message
    endif
    let a:entry.type = type
endfunction

function! neomake#makers#ft#elixir#EnabledMakers() abort
    return ['mix']
endfunction

function! neomake#makers#ft#elixir#elixir() abort
    return {
        \ 'errorformat':
            \ '%E** %s %f:%l: %m,'.
            \ '%W%f:%l: warning: %m'
        \ }
endfunction

function! neomake#makers#ft#elixir#credo() abort
    return {
      \ 'exe': 'mix',
      \ 'args': ['credo', 'list', '%:p', '--format=oneline'],
      \ 'postprocess': function('neomake#makers#ft#elixir#PostprocessCredoErrorType'),
      \ 'errorformat':
          \'[%t] %. %f:%l:%c %m,' .
          \'[%t] %. %f:%l %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#mix() abort
    return {
      \ 'exe' : 'mix',
      \ 'args': ['compile', '--warnings-as-errors'],
      \ 'postprocess': function('neomake#makers#ft#elixir#PostprocessEnforceMaxBufferLine'),
      \ 'errorformat':
        \ '** %s %f:%l: %m,'.
        \ '%f:%l: warning: %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#dogma() abort
    return {
      \ 'exe': 'mix',
      \ 'args': ['dogma', '%:p', '--format=flycheck'],
      \ 'errorformat': '%E%f:%l:%c: %.: %m'
      \ }
endfunction
