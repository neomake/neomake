function! neomake#makers#ft#lua#EnabledMakers() abort
    return executable('luacheck') ? ['luacheck'] : ['luac']
endfunction

function! neomake#makers#ft#lua#luacheck() abort
    " cwd: luacheck looks for .luacheckrc upwards from there.
    return {
        \ 'args': ['--no-color', '--formatter=plain', '--codes', '--filename', '%:p'],
        \ 'cwd': '%:p:h',
        \ 'errorformat': '%f:%l:%c: \(%t%n\) %m',
        \ 'postprocess': function('neomake#postprocess#GenericLengthPostprocess'),
        \ 'supports_stdin': 1,
        \ }
endfunction

function! neomake#makers#ft#lua#luac() abort
    return {
        \ 'args': ['-p'],
        \ 'errorformat': '%*\f: %#%f:%l: %m',
        \ }
endfunction
