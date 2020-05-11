function! neomake#makers#ft#proto#EnabledMakers() abort
    return ['prototool', 'buf']
endfunction

function! neomake#makers#ft#proto#prototool() abort
    return {
                \ 'exe': 'prototool',
                \ 'args': ['lint'],
                \ 'errorformat': '%f:%l:%c:%m',
                \ }
endfunction

function! neomake#makers#ft#proto#process_output_buf(context) abort
    let entries = []
    for line in a:context['output']
        let data = json_decode(line)
        let entry = {
                    \ 'maker_name': 'buf',
                    \ 'filename': data.path,
                    \ 'text': data.message,
                    \ 'lnum': data.start_line,
                    \ 'col': data.start_column,
                    \ 'type': data.type,
                    \ }
        call add(entries, entry)
    endfor
    return entries
endfunction

function! neomake#makers#ft#proto#buf() abort
    return {
                \ 'exe': 'buf',
                \ 'args': ['check', 'lint', '--error-format=json', '--file'],
                \ 'process_output': function('neomake#makers#ft#proto#process_output_buf')
                \ }
endfunction
" vim: ts=4 sw=4 et
