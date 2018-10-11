function! neomake#makers#ft#dockerfile#EnabledMakers() abort
    return ['hadolint']
endfunction

function! neomake#makers#ft#dockerfile#hadolint() abort
    return {
          \ 'args': ['--format', 'tty'],
          \ 'errorformat': '%f:%l %m',
          \ }
endfunction
