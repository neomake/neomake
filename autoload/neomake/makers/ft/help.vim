function! neomake#makers#ft#help#EnabledMakers() abort
    let makers = ['proselint', 'writegood']
    if executable('vim')
        call insert(makers, 'vimhelplint')
    endif
    return makers
endfunction

let s:slash = neomake#utils#Slash()
let s:vimhelplint = executable('vimhelplint')
            \ ? 'vimhelplint'
            \ : expand('<sfile>:p:h:h:h:h:h', 1).s:slash.'contrib'.s:slash.'vimhelplint'

function! neomake#makers#ft#help#vimhelplint() abort
    return {
        \ 'exe': s:vimhelplint,
        \ 'errorformat': '%f:%l:%c:%trror:%n:%m,%f:%l:%c:%tarning:%n:%m',
        \ 'postprocess': function('neomake#postprocess#GenericLengthPostprocess'),
        \ }
endfunction

function! neomake#makers#ft#help#proselint() abort
    return neomake#makers#ft#text#proselint()
endfunction

function! neomake#makers#ft#help#writegood() abort
    return neomake#makers#ft#text#writegood()
endfunction
