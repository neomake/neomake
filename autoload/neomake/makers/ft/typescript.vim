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
        \ 'filter_output': function('neomake#makers#ft#typescript#TslintFilterOutput'),
        \ 'process_json': function('neomake#makers#ft#typescript#TslintProcessJson'),
        \ 'args': ['--format', 'json'],
        \ 'output_stream': 'stdout',
        \ }
    let config = neomake#utils#FindGlobFile('tsconfig.json')
    if !empty(config)
        call extend(maker.args, ['--project', config])
        let maker.cwd = fnamemodify(config, ':h')
        let maker.tempfile_enabled = 0
    endif
    return maker
endfunction

function! neomake#makers#ft#typescript#TslintFilterOutput(lines, context) abort
    call filter(a:lines,
        \ { val -> v:val !~# '^''.\+'' is not included in project\.$' })
endfunction

function! neomake#makers#ft#typescript#TslintProcessJson(context) abort
    let errors = []
    for data in a:context['json']
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

    return errors
endfunction
