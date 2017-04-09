" vim: ts=4 sw=4 et

function! neomake#makers#ft#purescript#EnabledMakers() abort
    return ['pulp']
endfunction

function! neomake#makers#ft#purescript#pulp() abort
    " command is `pulp build --no-psa -- --json-errors`
    " as indicated in https://github.com/nwolverson/atom-ide-purescript/issues/136
    let maker = {
        \ 'args': ['build', '--no-psa', '--', '--json-errors'],
        \ 'append_file': 0,
        \ 'process_output': function('neomake#makers#ft#purescript#PSProcessOutput'),
        \ }

    " Find project root, since files are reported relative to it.
    let bower_file = neomake#utils#FindGlobFile('bower.json')
    if !empty(bower_file)
        let maker.cwd = fnamemodify(bower_file, ':h')
    endif

    return maker
endfunction

function! neomake#makers#ft#purescript#PSProcessOutput(context) abort
    let l:errors = []
    for line in a:context.output
        if line[0] !=# '{'
            continue
        endif
        let l:decoded = neomake#utils#JSONdecode(line)
        for [key, values] in items(l:decoded)
            let l:code = key ==# 'warnings' ? 'W' : 'E'
            for item in values
                let l:compiler_error = item['errorCode']
                let l:message = item['message']
                let l:position = item['position']
                let l:filename = item['filename']
                if  l:position is g:neomake#compat#json_null
                    let l:row = 1
                    let l:col = 1
                    let l:end_col = 1
                    let l:length = 1
                else
                    let l:row = l:position['startLine']
                    let l:col = l:position['startColumn']
                    let l:end_col = l:position['endColumn']
                    let l:length = l:end_col - l:col
                endif

                call add(l:errors, {
                            \ 'text': l:compiler_error . ' : ' . l:message,
                            \ 'type': l:code,
                            \ 'lnum': l:row,
                            \ 'col': l:col,
                            \ 'length': l:length,
                            \ 'filename': l:filename,
                            \ })
            endfor
        endfor
    endfor
    return l:errors
endfunction
