" vim: ts=4 sw=4 et

function! neomake#makers#ft#rust#EnabledMakers() abort
    return ['cargo']
endfunction

function! neomake#makers#ft#rust#rustc() abort
    return {
        \ 'errorformat':
            \ '%-Gerror: aborting due to previous error,'.
            \ '%-Gerror: aborting due to %\\d%\\+ previous errors,'.
            \ '%-Gerror: Could not compile `%s`.,'.
            \ '%Eerror[E%n]: %m,'.
            \ '%Eerror: %m,'.
            \ '%Wwarning: %m,'.
            \ '%Inote: %m,'.
            \ '%-Z\ %#-->\ %f:%l:%c,'.
            \ '%G\ %#\= %*[^:]: %m,'.
            \ '%G\ %#|\ %#%\\^%\\+ %m,'.
            \ '%I%>help:\ %#%m,'.
            \ '%Z\ %#%m,'.
            \ '%-G%s',
        \ }
endfunction

function! neomake#makers#ft#rust#cargo() abort
    return {
        \ 'args': ['test', '--no-run', '--message-format=json', '--quiet'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '[%t%n] "%f" %l:%v %m,'.
            \ '[%t] "%f" %l:%v %m',
        \ 'mapexpr': 'neomake#makers#ft#rust#CargoMapexpr(v:val)',
        \ 'postprocess': function('neomake#makers#ft#rust#CargoPostProcess')
        \ }
endfunction

function! neomake#makers#ft#rust#CargoMapexpr(val) abort
    let l:decoded = neomake#utils#JSONdecode(a:val)
    let l:data = get(l:decoded, 'message', -1)
    if type(l:data) == type({}) && len(l:data['spans'])
        let l:code_dict = get(l:data, 'code', -1)

        if l:code_dict is g:neomake#compat#json_null
            if get(l:data, 'level', '') ==# 'warning'
                let l:code = 'W'
            else
                let l:code = 'E'
            endif
        else
            let l:code = l:code_dict['code']
        endif
        let l:message = l:data['message']
        let l:span = l:data['spans'][0]
        let l:detail = l:span['label']
        let l:col = l:span['column_start']
        let l:row = l:span['line_start']
        let l:file = l:span['file_name']
        let l:length = l:span['byte_end'] - l:span['byte_start']
        let l:error = '[' . l:code . '] "' . l:file . '" ' .
                    \ l:row . ':' . l:col .  ' ' . l:length . ' ' .
                    \ l:message
        if type(l:detail) == type('') && len(l:detail)
            let l:error = l:error . ': ' . l:detail
        endif
        return l:error
    endif
endfunction

function! neomake#makers#ft#rust#CargoPostProcess(entry) abort
    let l:lines = split(a:entry.text, ' ')
    if len(l:lines)
        let a:entry.text = join(l:lines[1:])
        let a:entry.length = str2nr(l:lines[0])
    endif

endfunction
