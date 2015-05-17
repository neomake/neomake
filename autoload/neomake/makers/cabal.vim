" vim: ts=4 sw=4 et

" Note: buffer_output is not set to 1 to have real-time results,
" but Cabal multiline output can cause some troubles to neomake
" If errors are not properly parsed, try adding this line to your .vimrc
" let g:neomake_cabal_cabal_buffer_output = 1
function! neomake#makers#cabal#cabal()
    let errorformat = join([
                \ '%A%f:%l:%c:',
                \ '%A%f:%l:%c: %m',
                \ '%+C    %m',
                \ '%-Z%[%^ ]',
                \ ], ',')
    return {
        \ 'exe': 'cabal',
        \ 'args': ['build'],
        \ 'errorformat': errorformat
        \ }
endfunction
