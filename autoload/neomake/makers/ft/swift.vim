" vim: ts=4 sw=4 et

function! neomake#makers#ft#swift#EnabledMakers()
    return ['swiftc']
endfunction

function! neomake#makers#ft#swift#swiftc()
    " `export SDKROOT="$(xcodebuild -version -sdk macosx Path)"`
    return {
        \ 'args': ['-parse'],
        \ 'errorformat':
            \ '%E%f:%l:%c: error: %m,' .
            \ '%W%f:%l:%c: warning: %m,' .
            \ '%Z%\s%#^~%#,' .
            \ '%-G%.%#',
        \ }
endfunction
