" vim: ts=4 sw=4 et

function! neomake#makers#ft#elm#EnabledMakers() abort
    return ['elmMake']
endfunction

function! neomake#makers#ft#elm#elmMake() abort
    return {
        \ 'exe': 'elm-make',
        \ 'args': ['--report=json', '--output=' . neomake#utils#DevNull()],
        \ 'mapexpr': 'neomake#makers#ft#elm#ElmMakeMapexpr(v:val)',
        \ 'errorformat':
            \ '[%t%n] "%f" %l:%v %m,'.
            \ '[%t] "%f" %l:%v %m',
        \ 'postprocess': function('neomake#makers#ft#elm#ElmMakePostProcess')
        \ }
endfunction

function! neomake#makers#ft#elm#ElmMakeMapexpr(val) abort
    if a:val[0] !=# '['
        return
    endif
    let l:decoded = neomake#utils#JSONdecode(a:val)
    if type(l:decoded) == type([])
      for item in l:decoded
        if get(item, 'type', '') ==# 'warning'
          let l:code = 'W'
        else
          let l:code = 'E'
        endif

        let l:type = item['tag']
        let l:message = item['overview']
        let l:region_start = item['region']['start']
        let l:region_end = item['region']['end']
        let l:row = l:region_start['line']
        let l:col = l:region_start['column']
        let l:length = l:region_end['column'] - l:region_start['column']
        let l:file = item['file']

        let l:error = '[' . l:code . '] "' . l:file . '" ' .
                    \ l:row . ':' . l:col .  ' ' . l:length . ' ' .
                    \ l:type . ' : ' . l:message
        return l:error
      endfor
    endif
endfunction

function! neomake#makers#ft#elm#ElmMakePostProcess(entry) abort
    let l:lines = split(a:entry.text, ' ')
    if len(l:lines)
        let a:entry.text = join(l:lines[1:])
        let a:entry.length = str2nr(l:lines[0])
    endif
endfunction
