" vim: ts=4 sw=4 et

function! neomake#makers#ft#java#EnabledMakers()
    return ['javac']
endfunction

function! neomake#makers#ft#java#javac()
    let args = ['-Xlint']
    let arg_d = []
    if exists("g:neomake_java_javac_class_output_folder")
        let arg_d = ['-d', fnameescape(expand(g:neomake_java_javac_class_output_folder))]
    else
        if neomake#utils#IsRunningWindows()
            let arg_d = ['-d', 'C:/tmp/' . neomake#utils#Random()]
        else
            let arg_d = ['-d', '/tmp/' . neomake#utils#Random()]
            echomsg("this branch executed")
        endif
    endif
    let args += arg_d
    echo args
    return {
        \ 'exe' : 'javac',
        \ 'args': args,
        \ 'errorformat':
            \ '%E%f:%l: error: %m,' .
            \ '%W%f:%l: warning: %m,' .
            \ '%A%f:%l: %m,' .
            \ '%+Z%p^,' .
            \ '%+C%.%#,' .
            \ '%-G%.%#',
         \ }
endfunction
