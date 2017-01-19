" vim: ts=4 sw=4 et

function! neomake#makers#cargo#cargo() abort
    return {
        \ 'args': ['test', '--no-run', '--message-format=json', '--quiet'],
        \ 'errorformat':
            \ '[%t%n] "%f" %l:%v %m',
        \ 'mapexpr': "neomake#makers#cargo#CargoParseJSON(v:val)",
        \ }
endfunction

function! neomake#makers#cargo#CargoParseJSON(val) abort
    let l:text = a:val
    if l:text[0] == '{'
        let l:data = get(json_decode(l:text), 'message', {})
        let l:code = get(l:data, 'code', v:null)
        if type(l:code) == type({})
            let l:code = l:code['code']
            let l:message = l:data['message']
            let l:span = l:data['spans'][0]
            let l:detail = l:span['label']
            let l:col = l:span['column_start']
            let l:row = l:span['line_start']
            let l:file = l:span['file_name']
            let l:error = '[' . l:code . '] "' . l:file . '" ' .
                        \ l:row . ':' .l:col .  ' ' .
                        \ l:message . ': ' . l:detail
            return l:error
        endif
    endif
endfunction
