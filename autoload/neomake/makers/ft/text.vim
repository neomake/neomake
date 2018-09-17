function! neomake#makers#ft#text#EnabledMakers() abort
    " No makers enabled by default, since text is used as fallback often.
    return []
endfunction

function! neomake#makers#ft#text#proselint() abort
    return {
          \ 'errorformat': '%W%f:%l:%c: %m',
          \ 'postprocess': function('neomake#postprocess#generic_length'),
          \ }
endfunction

function! neomake#makers#ft#text#PostprocessWritegood(entry) abort
    let a:entry.col += 1
    if a:entry.text[0] ==# '"'
      let matchend = match(a:entry.text, '\v^[^"]+\zs"', 1)
      if matchend != -1
        let a:entry.length = matchend - 1
      endif
    endif
endfunction

function! neomake#makers#ft#text#writegood() abort
    return {
                \ 'args': ['--parse'],
                \ 'errorformat': '%W%f:%l:%c:%m,%C%m,%-G',
                \ 'postprocess': function('neomake#makers#ft#text#PostprocessWritegood'),
                \ }
endfunction

function! neomake#makers#ft#text#GetEntriesForOutput_Redpen(context) abort
    if a:context.source ==# 'stderr'
        return []
    endif
    let output = neomake#utils#JSONdecode(join(a:context.output, ''))
    call neomake#utils#DebugObject('context', a:context)
    if !len(output)
        return []
    endif

    " Input is a list from CLI, but just a dict via curl/redpen-server.
    if type(output) == type([])
        let result = output[0]
    else
        let result = output
    endif

    let entries = []
    " for o in output
    for error in get(result, 'errors', [])
        let type = 'E'
        let text = get(error, 'message')
        let validator = get(error, 'validator')
        if len(validator)
            let text .= ' ['.validator.']'
            if validator ==# 'Spelling'
                let type = 'W'
            endif
        endif

        let entry = {
                    \ 'text': text,
                    \ 'lnum': get(error, 'lineNum', 0),
                    \ 'type': type,
                    \ 'bufnr': a:context.jobinfo.bufnr,
                    \ }

        if has_key(get(error, 'startPosition', {}), 'offset')
            let entry.col = error.startPosition.offset + 1
            if has_key(get(error, 'endPosition', {}), 'offset')
                let entry.length = error.endPosition.offset - entry.col + 1
            endif
        endif

        call add(entries, entry)
    endfor
    " endfor
    return entries
endfunction

function! neomake#makers#ft#text#redpen() abort
          " \ 'postprocess': function('neomake#postprocess#GenericLengthPostprocess'),
    return {
          \ 'args': ['--result-format', 'json'],
          \ 'process_output': function('neomake#makers#ft#text#GetEntriesForOutput_Redpen'),
          \ }
endfunction

function! s:redpen_curl_cb(jobinfo) abort dict
    " TODO: is fts available already?!
    let format = index(split(a:jobinfo.ft, '\.'), 'markdown') != 1 ? 'MARKDOWN' : 'PLAIN'  " would also have WIKI
    " XXX: update method to get filename!
    let self.args = ['-s', '--data-urlencode',
                \ printf('document@%s', fnameescape(neomake#utils#get_fname_for_buffer(a:jobinfo))),
                \ printf('format=%s', format),
                \ printf('lang=%s', get(split(&spelllang, ','), 0, 'en')),
                \ 'http://localhost:8080/rest/document/validate']
endfunction

function! neomake#makers#ft#text#redpen_curl() abort
          " \ 'postprocess': function('neomake#postprocess#GenericLengthPostprocess'),
    return {
          \ 'exe': 'curl',
          \ 'fn': function('s:redpen_curl_cb'),
          \ 'process_output': function('neomake#makers#ft#text#GetEntriesForOutput_Redpen'),
          \ }
endfunction
