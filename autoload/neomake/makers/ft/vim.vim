" vim: ts=4 sw=4 et

function! neomake#makers#ft#vim#EnabledMakers() abort
    return ['vint', 'vimlint']
endfunction

function! neomake#makers#ft#vim#vint() abort
    let l:args = ['--style-problem', '-f', '--no-color',
        \ '{file_path}:{line_number}:{column_number}:{severity}:{description} ({policy_name})']

    if has('nvim')
        call add(l:args, '--enable-neovim')
    endif

    return {
        \ 'args': l:args,
        \ 'errorformat': '%f:%l:%c:%t%*[^:]:%m'
        \ }
endfunction

function! neomake#makers#ft#vim#vimlint() abort
    return {
        \ 'errorformat': '%f:%l:%c:%t%*[^:]: %m'
        \ }
endfunction
