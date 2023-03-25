" vim: ts=4 sw=4 et

function! neomake#makers#ft#swift#EnabledMakers() abort
    let ret = ['swiftc']
    if !empty(s:get_swiftpm_config())
        let ret = ['swiftpm']
    endif
    if s:get_swiftlint_config()
        let ret = add(ret, 'swiftlint')
    endif
    return ret
endfunction

function! s:get_swiftpm_config() abort
    return neomake#utils#FindGlobFile('Package.swift')
endfunction

function! s:get_swiftlint_config() abort
    return executable('swiftlint') && !empty(neomake#utils#FindGlobFile('.swiftlint.yml'))
endfunction

function! s:get_swiftpm_base_maker() abort
    let maker = {
        \ 'exe': 'swift',
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f:%l:%c: error: %m,' .
            \ '%E%f:%l: error: %m,' .
            \ '%E%f: error: %m,' .
            \ '%W%f:%l:%c: warning: %m,' .
            \ '%Z%\s%#^~%#,' .
            \ '%-G%.%#',
        \ }
    let config = s:get_swiftpm_config()
    if !empty(config)
        let maker.cwd = fnamemodify(config, ':h')
    endif
    return maker
endfunction

function! neomake#makers#ft#swift#swiftpm() abort
    let maker = s:get_swiftpm_base_maker()
    let maker.args = ['build', '--build-tests']
    return maker
endfunction

function! neomake#makers#ft#swift#swiftpmtest() abort
    let maker = s:get_swiftpm_base_maker()
    let maker.args = ['test']
    return maker
endfunction

function! neomake#makers#ft#swift#swiftfile() abort
    let maker = s:get_swiftpm_base_maker()
    let maker.append_file = 1
    return maker
endfunction

function! neomake#makers#ft#swift#swiftlint() abort
    return {
        \ 'args': ['lint', '--quiet'],
        \ 'append_file': 1,
        \ 'errorformat':
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l: %trror: %m,' .
            \ '%f:%l: %tarning: %m',
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
