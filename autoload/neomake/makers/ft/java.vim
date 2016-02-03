let s:save_cpo = &cpo
set cpo&vim

if exists('g:neomake_java_javac_maker')
    finish
endif

function! s:getClasspath() abort
    return '.'
endfunction
let g:neomake_java_javac_option =
            \get(g:,'neomake_java_javac_option','-Xlint')
let g:neomake_java_javac_outputdir =
            \get(g:,'neomake_java_javac_outputdir','.')
let g:neomake_java_javac_classpath =
            \get(g:,'neomake_java_javac_classpath',s:getClasspath())


function! neomake#makers#ft#java#EnabledMakers()
        return ['javac']
endfunction

function! neomake#makers#ft#java#javac()
    return {
                \ 'args':[
                \g:neomake_java_javac_option,
                \'-cp',g:neomake_java_javac_classpath,
                \'-d',g:neomake_java_javac_outputdir
                \],
                \ 'errorformat':
                \ '%E%f:%l: error: %m,'.
                \ '%W%f:%l: warning: %m,'.
                \ '%E%f:%l: %m,'.
                \ '%Z%p^,'.
                \ '%-G%.%#'
                \ }
endfunction

let g:neomake_java_javac_maker = 1
let &cpo = s:save_cpo
unlet s:save_cpo
