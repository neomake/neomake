function! neomake#makers#ft#text#EnabledMakers() abort
    " No makers enabled by default, since text is used as fallback often.
    return []
endfunction

function! neomake#makers#ft#text#proselint() abort
    return {
          \ 'errorformat': '%W%f:%l:%c: %m',
          \ 'postprocess': function('neomake#postprocess#GenericLengthPostprocess'),
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

function! s:fn_languagetool_curl(jobinfo) abort dict
    " XXX: update method to get filename!
    let self.args = ['-s',
                \ '--data-urlencode', printf('text@%s', fnameescape(fnamemodify(bufname(a:jobinfo.bufnr), ':p'))),
                \ '--data-urlencode', printf('language=%s', get(split(&spelllang, ','), 0, 'en')),
		\ '--data-urlencode', printf('motherTongue=%s', 'pt-PT'),
                \ 'http://localhost:8081/v2/check']
endfunction

function! neomake#makers#ft#text#GetEntriesForOutput_LanguagetoolCurl(context) abort
    if a:context.source ==# 'stderr'
        return []
    endif
    let output = neomake#utils#JSONdecode(join(a:context.output, ''))
    call neomake#utils#DebugObject('output', output)
    if !len(output)
        return []
    endif

    let entries = []
    for _m in get(output, 'matches', [])
        let offset = get(_m, 'offset') + 0
        let length = get(_m, 'length') + 0
        let rule = get(_m, 'rule')
        let rule_id = get(rule, 'id')
        let rule_type = get(rule, 'issueType')
        let message_long = get(_m, 'message')
        let message_short = get(_m, 'shortMessage')

        let message = ''
        if rule_type == 'misspelling'
            let type = 'E'
            let replacements = map(get(_m, 'replacements'), 'v:val.value')
            if !len(replacements)
                let message = message_long
            else
                let message = message_short . ' => ' . join((map(replacements,'"\"". v:val ."\""')), ' | ')
            endif
        else
            let type = 'W'
            let message = message_long
        endif

        let offset = offset
        let line_maybe = byte2line(offset)
        if line2byte(line_maybe + 1) == offset + 1
            " Next line starts in the next byte
            " This means the error is in the first character of the next line
            let line_num = line_maybe + 1
            let col_num = 1
        else
            let line_num = line_maybe
            let col_num = offset - line2byte(line_num) + 2
        endif
        let entry = {
                    \ 'text': message,
                    \ 'lnum': line_num,
                    \ 'col': col_num,
                    \ 'length': length,
                    \ 'type': type,
                    \ 'bufnr': a:context.jobinfo.bufnr,
                    \ }

        call add(entries, entry)
    endfor
    return entries
endfunction

function! neomake#makers#ft#text#languagetool_curl() abort
    return {
          \ 'exe': 'curl',
          \ 'fn': function('s:fn_languagetool_curl'),
          \ 'process_output': function('neomake#makers#ft#text#GetEntriesForOutput_LanguagetoolCurl'),
	  \ 'output_stream': 'stdout',
          \ }
endfunction
