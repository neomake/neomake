" vim: ts=4 sw=4 et

function! neomake#makers#ft#verilog#EnabledMakers()
    return ['iverilog']
endfunction

function! neomake#makers#ft#verilog#iverilog()
    return {
                \ 'args' : ['-t null', '-Wall'],
                \ 'errorformat' : '%f:%l: %trror: %m,' .
                \ '%f:%l: %tarning: %m,' .
                \ '%E%f:%l:      : %m,' .
                \ '%W%f:%l:        : %m,' .
                \ '%f:%l: %m',
                \ }
endfunction
