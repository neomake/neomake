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
        \ 'errorformat': '%I%f:%l:%c:style_problem:%m,'
        \   .'%f:%l:%c:%t%*[^:]:E%n: %m,'
        \   .'%f:%l:%c:%t%*[^:]:%m',
        \ 'output_stream': 'stdout',
        \ 'postprocess': {
        \   'fn': function('neomake#postprocess#GenericLengthPostprocess'),
        \   'pattern': '\v(Undefined variable: |:)\zs([^ ]+)',
        \ }}
endfunction

function! neomake#makers#ft#vim#vimlint() abort
    return {
        \ 'args': ['-u'],
        \ 'errorformat': '%f:%l:%c:%trror: EVL%n: %m,'
        \   . '%f:%l:%c:%tarning: EVL%n: %m,'
        \   . '%f:%l:%c:%t%*[^:]: EVP_%#E%#%n: %m',
        \ 'postprocess': function('neomake#makers#ft#vim#PostprocessVimlint'),
        \ 'output_stream': 'stdout',
        \ }
endfunction

function! neomake#makers#ft#vim#PostprocessVimlint(entry) abort
    let m = matchlist(a:entry.text, '\v`\zs[^`]{-}\ze`')
    if empty(m)
        return
    endif

    " Ensure that the text is there.
    let l = len(m[0])
    let line = getline(a:entry.lnum)
    if line[a:entry.col-1 : a:entry.col-2+l] == m[0]
        let a:entry.length = l
    elseif m[0][0:1] ==# 'l:' && line[a:entry.col-1 : a:entry.col-4+l] == m[0][2:]
        " Ignore implicit 'l:' prefix.
        let a:entry.length = l - 2
    endif
endfunction
