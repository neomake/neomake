function! s:getVar(varname, default) abort
    return get(b:, a:varname, get(g:, a:varname, a:default))
endfunction

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
    let defaultFallbackLanguage = 'en'  " Without variants there is no spell checking
    let language = s:getVar('neomake_text_languagetool_curl_language',
                \ get(split(&spelllang, ','), 0, defaultFallbackLanguage) )
    " XXX: update method to get filename!
    let l:args = ['-s',
                \ '--data-urlencode', printf('text@%s', fnameescape(fnamemodify(bufname(a:jobinfo.bufnr), ':p'))),
                \ '--data-urlencode', printf('language=%s', language),
                \ ]
    let motherTongue = s:getVar('neomake_text_languagetool_curl_motherTongue', v:null)
    if motherTongue != v:null
        let args += ['--data-urlencode', printf('motherTongue=%s', motherTongue)]
    endif
    let preferredVariants = s:getVar('neomake_text_languagetool_curl_preferredVariants', v:null)
    if l:preferredVariants != v:null && l:language == 'auto'
        let args += ['--data-urlencode', printf('preferredVariants', join(preferredVariants, ','))]
    endif
    " Public API: https://languagetool.org/api
    let server = s:getVar('neomake_text_languagetool_curl_server', 'http://localhost:8081')
    let args += [printf('%s/v2/check', server)]
    let self.args = args
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

    let current_file = join(getline('^', '$'), "\r")
    let line_delta = {}

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

        let previous_chars = split(current_file[:offset], '\zs')
        let line_num = count(previous_chars, "\r") + 1 " Count the number of newlines before this index
        let line_offset = len(previous_chars) - index(reverse(copy(previous_chars)), "\r") - 1
        let col_num = offset - line_offset + get(line_delta, line_num, 0) " Count from the last newline to the offset

        " When the segment has non-ASCII characters, add a delta
        let segment = split(current_file, '\zs')[offset:offset + length - 1]
        call neomake#utils#DebugMessage('O['.offset.']: '.string(segment))
        let len_list = len(segment)
        let len_str = len(join(segment, ''))
        if len_list != len_str
            let current_delta = len_str - len_list
            let length = length + current_delta
            let line_delta[line_num] = get(line_delta, line_num, 0) + current_delta
            call neomake#utils#DebugMessage('  Delta: '.current_delta)
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
                \ 'append_file': 0,
                \ }
endfunction
