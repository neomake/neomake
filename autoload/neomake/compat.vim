" Function to wrap Compatibility across different (Neo)Vim versions.

if v:version >= 704
    function! neomake#compat#getbufvar(buf, key, def) abort
        return getbufvar(a:buf, a:key, a:def)
    endfunction
else
    function! neomake#compat#getbufvar(buf, key, def) abort
        return get(getbufvar(a:buf, ''), a:key, a:def)
    endfunction
endif

unlockvar neomake#compat#json_true
unlockvar neomake#compat#json_false
unlockvar neomake#compat#json_null

if exists('*json_decode')
    let neomake#compat#json_true = v:true
    let neomake#compat#json_false = v:false
    let neomake#compat#json_null = v:null

    function! neomake#compat#json_decode(json) abort
        return json_decode(a:json)
    endfunction
else
    let neomake#compat#json_true = 1
    let neomake#compat#json_false = 0
    function! s:json_null() abort
    endfunction
    let neomake#compat#json_null = [function('s:json_null')]

    " Via Syntastic (https://github.com/vim-syntastic/syntastic/blob/6fb14d624b6081459360fdbba743f82cf84c8f92/autoload/syntastic/preprocess.vim#L576-L607),
    " based on https://github.com/MarcWeber/vim-addon-json-encoding/blob/master/autoload/json_encoding.vim.
    " @vimlint(EVL102, 1, l:true)
    " @vimlint(EVL102, 1, l:false)
    " @vimlint(EVL102, 1, l:null)
    function! neomake#compat#json_decode(json) abort " {{{2
        if a:json ==# ''
            return []
        endif

        " The following is inspired by https://github.com/MarcWeber/vim-addon-manager and
        " http://stackoverflow.com/questions/17751186/iterating-over-a-string-in-vimscript-or-parse-a-json-file/19105763#19105763
        " A hat tip to Marc Weber for this trick
        if substitute(a:json, '\v\"%(\\.|[^"\\])*\"|true|false|null|[+-]?\d+%(\.\d+%([Ee][+-]?\d+)?)?', '', 'g') !~# "[^,:{}[\\] \t]"
            " JSON artifacts
            let true = g:neomake#compat#json_true
            let false = g:neomake#compat#json_false
            let null = g:neomake#compat#json_null

            try
                let object = eval(a:json)
            catch
                " malformed JSON
                let object = ''
            endtry
        else
            let object = ''
        endif

        return object
    endfunction " }}}2
    " @vimlint(EVL102, 0, l:true)
    " @vimlint(EVL102, 0, l:false)
    " @vimlint(EVL102, 0, l:null)
endif

lockvar neomake#compat#json_true
lockvar neomake#compat#json_false
lockvar neomake#compat#json_null

if exists('*uniq')
    function! neomake#compat#uniq(l) abort
        return uniq(a:l)
    endfunction
else
    " From ingo#collections#UniqueSorted.
    function! neomake#compat#uniq(l) abort
        if len(a:l) < 2
            return a:l
        endif

        let l:previousItem = a:l[0]
        let l:result = [a:l[0]]
        for l:item in a:l[1:]
            if l:item !=# l:previousItem
                call add(l:result, l:item)
                let l:previousItem = l:item
            endif
        endfor
        return l:result
    endfunction
endif

if exists('*reltimefloat')
    function! neomake#compat#reltimefloat() abort
        return reltimefloat(reltime())
    endfunction
else
    function! neomake#compat#reltimefloat() abort
        let t = split(reltimestr(reltime()), '\V.')
        return str2float(t[0] . '.' . t[1])
    endfunction
endif

" Wrapper around systemlist() that supports a list for a:cmd.
" It returns an empty string on error.
" NOTE: Neovim before 0.2.0 would throw an error (which is caught), but it
" does not set v:shell_error!
function! neomake#compat#systemlist(cmd) abort
    if empty(a:cmd)
        return []
    endif
    if has('nvim') && exists('*systemlist')
        " @vimlint(EVL108, 1)
        if !has('nvim-0.2.0')
            try
                return systemlist(a:cmd)
            catch /^Vim\%((\a\+)\)\=:E902/
                return ''
            endtry
        endif
        " @vimlint(EVL108, 0)
        return systemlist(a:cmd)
    endif

    if type(a:cmd) == type([])
        let cmd = join(map(a:cmd, 'neomake#utils#shellescape(v:val)'))
    else
        let cmd = a:cmd
    endif
    if exists('*systemlist')
        return systemlist(cmd)
    endif
    return split(system(cmd), '\n')
endfunction
