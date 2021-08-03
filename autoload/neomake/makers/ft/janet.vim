" vim: ts=4 sw=4 et

function! neomake#makers#ft#janet#EnabledMakers() abort
    return ['janetflycheck']
endfunction

function! neomake#makers#ft#janet#janetflycheck() abort
    return {
        \ 'exe': 'janet',
        \ 'args': ['-k'],
        \ 'errorformat': '%f:%l:%c %m'
        \ }
endfunction
