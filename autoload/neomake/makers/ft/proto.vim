function! neomake#makers#ft#proto#EnabledMakers() abort
    return ['buf']
endfunction

function! neomake#makers#ft#proto#buf() abort
    return {
                \ 'exe': 'buf',
                \ 'args': ['check', 'lint', '--error-format=json', '--file'],
                \ 'process_output': function('neomake#makers#ft#proto#BufProcessOutput')
                \ }
endfunction

function! neomake#makers#ft#proto#BufProcessOutput(context) abort
    let entries = []
    for line in a:context['output']
        let data = neomake#compat#json_decode(line)
        let entry = {
                    \ 'filename': data.path,
                    \ 'text': data.message,
                    \ 'lnum': data.start_line,
                    \ 'col': data.start_column,
                    \ 'type': s:typeTranslation(data.type),
                    \ }
        call add(entries, entry)
    endfor
    return entries
endfunction

function! s:typeTranslation(typeName) abort
    if a:typeName ==# 'COMPILE'
        return 'ERROR'
    endif
    return 'WARNING'
endfunction
" vim: ts=4 sw=4 et
