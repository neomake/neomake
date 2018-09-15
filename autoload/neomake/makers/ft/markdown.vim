function! neomake#makers#ft#markdown#SupersetOf() abort
    return 'text'
endfunction

function! neomake#makers#ft#markdown#EnabledMakers() abort
    let makers = executable('mdl') ? ['mdl'] : ['markdownlint']
    if executable('vale') | let makers += ['vale'] | endif
    return makers + ['writegood'] + neomake#makers#ft#text#EnabledMakers()
endfunction

function! neomake#makers#ft#markdown#mdl() abort
    return {
        \
        \ 'errorformat':
        \   '%W%f:%l: MD%n %m,' .
        \   '%W%f:%l: %m',
        \ 'output_stream': 'stdout',
        \ }
endfunction

function! neomake#makers#ft#markdown#markdownlint() abort
    return {
        \ 'errorformat': '%f: %l: %m'
        \ }
endfunction

function! neomake#makers#ft#markdown#alex() abort
    return {
        \ 'errorformat':
        \   '%P%f,'
        \   .'%-Q,'
        \   .'%*[ ]%l:%c-%*\d:%n%*[ ]%tarning%*[ ]%m,'
        \   .'%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#markdown#ProcessVale(context) abort
    let entries = []
    for [filename, items] in items(a:context['json'])
      for data in items
        let entry = {
            \ 'maker_name': 'vale',
            \ 'filename': filename,
            \ 'text': data.Message,
            \ 'lnum': data.Line,
            \ 'col': data.Span[0],
            \ 'length': data.Span[1] - data.Span[0] + 1,
            \ 'type': toupper(data.Severity[0])
            \ }
        call add(entries, entry)
      endfor
    endfor
    return entries
endfunction

function! neomake#makers#ft#markdown#vale() abort
    return {
        \ 'args': [
        \   '--no-wrap',
        \   '--output', 'JSON'
        \ ],
        \ 'process_json': function('neomake#makers#ft#markdown#ProcessVale')
        \ }
endfunction
