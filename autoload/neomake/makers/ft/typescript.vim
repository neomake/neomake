" vim: ts=4 sw=4 et

function! neomake#makers#ft#typescript#EnabledMakers() abort
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#typescript#tsc() abort
    " tsc should not be passed a single file.
    let maker = {
        \ 'args': ['--noEmit', '--watch', 'false', '--pretty', 'false'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f %#(%l\,%c): error %m,' .
            \ '%E%f %#(%l\,%c): %m,' .
            \ '%Eerror %m,' .
            \ '%C%\s%\+%m'
        \ }
    let config = neomake#utils#FindGlobFile('tsconfig.json')
    if !empty(config)
        let maker.args += ['--project', config]
    endif
    return maker
endfunction

function! neomake#makers#ft#typescript#tslint() abort
    let maker = {
        \ 'process_output': function('neomake#makers#ft#typescript#TslintProcessOutput'),
        \ 'args': ['--format', 'json'],
        \ }
    let config = neomake#utils#FindGlobFile('tsconfig.json')
    if !empty(config)
        call extend(maker.args, ['--project', config])
        let maker.cwd = fnamemodify(config, ':h')
        let maker.tempfile_enabled = 0
    endif
    return maker
endfunction

function! neomake#makers#ft#typescript#TslintProcessOutput(context) abort
    let errors = []
    for line in a:context['output']
        let decoded = neomake#utils#JSONdecode(line)
        for data in decoded
            let error = {
                \ 'maker_name': 'tslint',
                \ 'filename': data.name,
                \ 'text': data.failure,
                \ 'lnum': data.startPosition.line + 1,
                \ 'col': data.startPosition.character + 1,
                \ 'length': data.endPosition.position - data.startPosition.position,
                \ }
            if get(data, 'ruleSeverity') ==# 'WARNING'
                let error.type = 'W'
            else
                let error.type = 'E'
            endif

            call add(errors, error)
        endfor
    endfor

    return errors
endfunction
