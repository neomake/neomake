let s:slash = neomake#utils#Slash()

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

" See http://wiki.languagetool.org/public-http-api for a public instance. Use:
"   :let g:neomake_text_languagetool_server = 'https://languagetool.org/api'
let s:languagetool_maker = {
            \   'name': 'languagetool',
            \   'exe': expand('<sfile>:p:h', 1).s:slash.'text'.s:slash.'languagetool.py',
            \   'append_file': 1,
            \ }
function! s:languagetool_maker.InitForJob(jobinfo) abort
    let args = []
    " Mandatory arguments
    let server = neomake#utils#GetSetting('server', s:languagetool_maker, 'http://localhost:8081', a:jobinfo.ft, a:jobinfo.bufnr)
    let language = neomake#utils#GetSetting('language', s:languagetool_maker,
                \ get(split(&spelllang, ','), 0,
                \   neomake#utils#GetSetting('fallbacklanguage', s:languagetool_maker, 'auto', a:jobinfo.ft, a:jobinfo.bufnr)
                \ ),
                \ a:jobinfo.ft, a:jobinfo.bufnr)
    let args += [server, language]
    let self.args = args
endfunction

function! s:languagetool_maker.process_output(context) abort
    let output = neomake#utils#JSONdecode(join(a:context.output, ''))
    call neomake#log#debug_obj('output', output)
    let entries = []

    for _m in output
        let entry = _m
        let _m['bufnr'] = a:context.jobinfo.bufnr
        call add(entries, entry)
    endfor

    return entries
endfunction

function! neomake#makers#ft#text#languagetool() abort
        " \ 'supports_stdin': 1,
    return copy(s:languagetool_maker)
endfunction

" vim: ts=4 sw=4 et
