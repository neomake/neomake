" vim: ts=4 sw=4 et

function! neomake#makers#ft#clojure#EnabledMakers() abort
    return ['lein']
endfunction

function! neomake#makers#ft#clojure#lein() abort
    return {
                \ 'args': 'check',
                \ 'append_file': 0,
                \ 'process_output': function('neomake#makers#ft#clojure#LeinProcessOutput'),
                \ }
endfunction

function! neomake#makers#ft#clojure#LeinProcessOutput(entry) abort
    let errors = []
    for line in a:entry['output']
        if line =~# '^Exception'
            " Example error:
            " Exception ...: Parameter declaration "!" should be a vector, compiling:(dir/file.cljc:3:1)
            let error = { 'type': 'E' }

            " Remove the exception's name, split at ", compiling:("
            let parts = split(substitute(line, '^[^:]\+: ', '', ''), ', compiling:(')

            " Keep only what's before ", compiling:("
            let error.text = parts[0]

            " Get the part of the string after ", compiling:("
            let file_num_char = parts[1]

            " Get the part before any colon, remove any dir name
            let error.filename = fnamemodify(substitute(file_num_char, ':.\+', '', ''), ':t')

            " Remove everything that isn't between two colons
            let error.lnum = substitute(file_num_char, '[^:]\+:\([^:]\+\):[^)]\+)', '\1', '')

            " Remove everything that isn't between the last colon and the last paren
            let error.col = substitute(file_num_char, '[^:]\+:[^:]\+:\([^)]\+\))', '\1', '')

            call add(errors, error)
        endif
    endfor
    return errors
endfunction
