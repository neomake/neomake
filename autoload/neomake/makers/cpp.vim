" vim: ts=4 sw=4 et

function! neomake#makers#cpp#EnabledMakers()
    return ['clang']
endfunction

function! neomake#makers#cpp#clang()
    let maker = neomake#makers#c#clang()
    let maker.exe = 'clang++'
    return maker
endfunction
