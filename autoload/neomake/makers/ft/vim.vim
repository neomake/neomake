" vim: ts=4 sw=4 et

function! neomake#makers#ft#vim#EnabledMakers() abort
    return ['vint']
endfunction

function! neomake#makers#ft#vim#vint() abort
    let l:args = ['--style-problem', '--no-color',
        \ '-f', '{file_path}:{line_number}:{column_number}:{severity}:{description} ({policy_name})']

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
        \ 'args': ['-u'],
        \ 'errorformat': '%f:%l:%c:%trror: EVL%n: %m,'
        \   . '%f:%l:%c:%tarning: EVL%n: %m',
        \ }
endfunction
