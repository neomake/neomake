function! neomake#makers#ft#jinja#tidy() abort
    " Args:
    " - --show-body-only true: for partial templates, skipping
    "   "Warning: missing <!DOCTYPE> declaration",
    "   "Warning: inserting implicit <body>" etc.
    let maker = neomake#makers#ft#html#tidy()
    let maker.args += [
                \ '--show-body-only', 'true',
                \ ]
    return maker
endfunction

function! neomake#makers#ft#jinja#htmlhint() abort
    " NOTE: requires a config (.htmlhintrc) with "doctype-first": false.
    return neomake#makers#ft#html#htmlhint()
endfunction


function! neomake#makers#ft#jinja#EnabledMakers() abort
    return ['tidy']
endfunction
" vim: ts=4 sw=4 et
