command! -nargs=? Neomake call neomake#Make(<f-args>)

augroup neomake
    autocmd!
    au JobActivity neomake* call neomake#MakeHandler()
augroup END
