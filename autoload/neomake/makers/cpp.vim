" vim: ts=4 sw=4 et

function! neomake#makers#cpp#EnabledMakers()
    if neomake#utils#Exists('clang++')
        return ['clang']
    else
        return ['gcc']
    end
endfunction

function! neomake#makers#cpp#clang()
    let maker = neomake#makers#c#clang()
    let maker.exe = 'clang++'
    return maker
endfunction

function! neomake#makers#cpp#gcc()
    let maker = neomake#makers#c#gcc()
    let maker.exe = 'g++'
    return maker
endfunction
