" vim: ts=4 sw=4 et

function! neomake#makers#ft#vhdl#EnabledMakers()
    if executable('ghdl')
        return ['ghdl']
    else
        return []
    endif
endfunction

function! neomake#makers#ft#vhdl#ghdl()
    return {
                \ 'args' : ['-s'],
                \ 'errorformat' : '%f:%l:%c: %m',
                \ }
endfunction
