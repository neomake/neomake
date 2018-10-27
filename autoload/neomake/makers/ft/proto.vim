function! neomake#makers#ft#proto#EnabledMakers() abort
    return ['prototool']
endfunction

function! neomake#makers#ft#proto#prototool() abort
    return {
                \ 'exe': 'prototool',
                \ 'args': ['lint'],
                \ 'errorformat': '%f:%l:%c:%m',
                \ }
endfunction
