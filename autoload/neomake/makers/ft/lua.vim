function! neomake#makers#ft#lua#EnabledMakers() abort
    return executable('luacheck') ? ['luacheck'] : ['luac']
endfunction

" luacheck: postprocess: use pattern (%s) for end column.
function! neomake#makers#ft#lua#PostprocessLuacheck(entry) abort
    let end_col = matchstr(a:entry.pattern, '\v\d+')
    if !empty(end_col)
        let a:entry.length = end_col - a:entry.col + 1
    else
        echom 'luacheck: no end_col: '.string(a:entry)
    endif
    let a:entry.pattern = ''
endfunction

function! neomake#makers#ft#lua#luacheck() abort
    " cwd: luacheck looks for .luacheckrc upwards from there.
    return {
        \ 'args': ['--no-color', '--formatter=plain', '--ranges', '--codes', '--filename', '%:p'],
        \ 'cwd': '%:p:h',
        \ 'errorformat': '%E%f:%l:%c-%s: \(%t%n\) %m',
        \ 'postprocess': function('neomake#makers#ft#lua#PostprocessLuacheck'),
        \ 'supports_stdin': 1,
        \ }
endfunction

function! neomake#makers#ft#lua#luac() abort
    return {
        \ 'args': ['-p'],
        \ 'errorformat': '%*\f: %#%f:%l: %m',
        \ }
endfunction
