" vim: ts=4 sw=4 et

function! neomake#makers#ft#elm#EnabledMakers() abort
    return ['elmMake']
endfunction

function! neomake#makers#ft#elm#elmMake() abort
    return {
        \ 'exe': 'elm-make',
        \ 'args': ['--report=json', '--output=' . neomake#utils#DevNull()],
        \ 'process_output': function('neomake#makers#ft#elm#ElmMakeProcessOutput')
        \ }
endfunction

function! neomake#makers#ft#elm#ElmMakeProcessOutput(context) abort
    let l:errors = []
    " output will be a List, containing either:
    " 1) A success message
    " 2) A string holding a JSON array for both warnings and errors

    for line in a:context.output
        if line[0] ==# '['
            let l:decoded = neomake#utils#JSONdecode(line)
            for item in l:decoded
                if get(item, 'type', '') ==# 'warning'
                    let l:code = 'W'
                else
                    let l:code = 'E'
                endif

                let l:compiler_error = item['tag']
                let l:message = item['overview']
                let l:filename = item['file']
                let l:region_start = item['region']['start']
                let l:region_end = item['region']['end']
                let l:row = l:region_start['line']
                let l:col = l:region_start['column']
                let l:length = l:region_end['column'] - l:region_start['column']

                let l:error = {
                            \ 'text': l:compiler_error . ' : ' . l:message,
                            \ 'type': l:code,
                            \ 'lnum': l:row,
                            \ 'col': l:col,
                            \ 'length': l:length,
                            \ 'filename': l:filename,
                            \ }
                call add(l:errors, l:error)
            endfor
        endif
    endfor
    return l:errors
endfunction
