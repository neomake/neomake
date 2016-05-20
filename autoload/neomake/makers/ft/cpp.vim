" vim: ts=4 sw=4 et

function! neomake#makers#ft#cpp#EnabledMakers()
    return executable('clang++') ? ['clang'] : ['gcc']
endfunction

function! neomake#makers#ft#cpp#clang()
    let maker = neomake#makers#ft#c#clang()
    let maker.exe = 'clang++'
    return maker
endfunction

function! neomake#makers#ft#cpp#gcc()
    let maker = neomake#makers#ft#c#gcc()
    let maker.exe = 'g++'
    return maker
endfunction

function! neomake#makers#ft#cpp#clangtidy()
    let maker = neomake#makers#ft#c#clangtidy()
    return maker
endfunction
