" vim: ts=4 sw=4 et

function! neomake#makers#ft#swift#EnabledMakers() abort
    let package = neomake#utils#FindGlobFile('Package.swift')
    if !empty(package)
        return ['swiftpm']
    else
        return ['swiftc']
    endif
endfunction

function! neomake#makers#ft#swift#swiftpm() abort
    return {
        \ 'exe': 'swift',
        \ 'args': ['build', '--build-tests'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f:%l:%c: error: %m,' .
            \ '%W%f:%l:%c: warning: %m,' .
            \ '%Z%\s%#^~%#,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#swift#swiftpmtest() abort
    return {
        \ 'exe': 'swift',
        \ 'args': ['test'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f:%l:%c: error: %m,' .
            \ '%E%f:%l: error: %m,' .
            \ '%W%f:%l:%c: warning: %m,' .
            \ '%Z%\s%#^~%#,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#swift#swiftc() abort
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
