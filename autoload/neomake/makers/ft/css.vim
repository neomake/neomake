scriptencoding utf8

let s:stylelint_skip_buffers = {}

function! neomake#makers#ft#css#EnabledMakers(...) abort
    let makers = ['csslint']
    if !a:0 || !get(s:stylelint_skip_buffers, a:1.bufnr, 0)
        let makers += ['stylelint']
    endif
    return makers
endfunction

function! neomake#makers#ft#css#csslint() abort
    return {
        \ 'args': ['--format=compact'],
        \ 'errorformat':
        \   '%-G,'.
        \   '%-G%f: lint free!,'.
        \   '%f: line %l\, col %c\, %trror - %m,'.
        \   '%f: line %l\, col %c\, %tarning - %m,'.
        \   '%f: line %l\, col %c\, %m,'.
        \   '%f: %tarning - %m'
        \ }
endfunction

function! neomake#makers#ft#css#stylelint() abort
    let maker = {
          \ 'errorformat':
          \   '%-P%f,'.
          \   '%W%*\s%l:%c%*\s✖  %m,'.
          \   '%-Q,'.
          \   '%+EError: No configuration provided for %f,%-C    %.%#'
          \ }

    function! maker.postprocess(entry) abort
        if a:entry.type ==# 'E' && a:entry.text =~# '\V\^Error: No configuration provided for'
            if !has_key(s:stylelint_skip_buffers, a:entry.bufnr)
                call neomake#log#warn_once(printf('Missing config for stylelint maker, removing from default config for this buffer: %s.',
                            \ a:entry.text),
                            \ printf('stylelint-skip-no-config-%d', a:entry.bufnr))
                let s:stylelint_skip_buffers[a:entry.bufnr] = 1
            endif
            return
        endif
        if has_key(s:stylelint_skip_buffers, a:entry.bufnr)
            unlet s:stylelint_skip_buffers[a:entry.bufnr]
        endif
        let a:entry.text = substitute(a:entry.text, '\v\s\s+(.{-})\s*$', ' [\1]', 'g')
    endfunction

    return maker
endfunction
" vim: ts=4 sw=4 et
