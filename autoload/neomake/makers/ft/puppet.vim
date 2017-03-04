function! neomake#makers#ft#puppet#EnabledMakers() abort
    return ['puppet', 'puppetlint']
endfunction

function! neomake#makers#ft#puppet#puppetlint() abort
    return {
        \ 'exe': 'puppet-lint',
        \ 'args': ['--log-format', '"%%{path}:%%{line}:%%{column}:%%{kind}:[%%{check}] %%{message}"'],
        \ 'errorformat': '"%f:%l:%c:%t%*[a-zA-Z]:%m"',
        \ }
endfunction

function! neomake#makers#ft#puppet#puppet() abort
    return {
        \ 'args': ['parser', 'validate', '--color=false'],
        \ 'errorformat':
        \   '%t%*[a-zA-Z]: %m at %f:%l:%c,'.
        \   '%t%*[a-zA-Z]: %m at %f:%l'
        \ }
endfunction
