" Debug/feedback helpers.

function! neomake#debug#validate_maker(maker) abort
    let issues = {'errors': [], 'warnings': []}

    if has_key(a:maker, 'process_json') && has_key(a:maker, 'process_output')
        let issues.warnings += ['maker has process_json and process_output, but only process_json will be used.']
        let check_process = ['process_json']
    else
        let check_process = ['process_json', 'process_output']
    endif

    for f in check_process
        if has_key(a:maker, f)
            if has_key(a:maker, 'mapexpr')
                let issues.warnings += [printf(
                            \ 'maker has mapexpr, but only %s will be used.',
                            \ f)]
            endif
            if has_key(a:maker, 'postprocess')
                let issues.warnings += [printf(
                            \ 'maker has postprocess, but only %s will be used.',
                            \ f)]
            endif
            if has_key(a:maker, 'errorformat')
                let issues.warnings += [printf(
                            \ 'maker has errorformat, but only %s will be used.',
                            \ f)]
            endif
        endif
    endfor

    if !executable(a:maker.exe)
        let t = get(a:maker, 'auto_enabled', 0) ? 'warnings' : 'errors'
        let issues[t] += [printf("maker's exe (%s) is not executable.", a:maker.exe)]
    endif

    return issues
endfunction

" Optional arg: ft
function! s:get_maker_info(...) abort
    let maker_names = call('neomake#GetEnabledMakers', a:000)
    if empty(maker_names)
        return ['None.']
    endif
    let maker_defaults = neomake#config#get('maker_defaults')
    let r = []
    for maker_name in maker_names
        let maker = call('neomake#GetMaker', [maker_name] + a:000)
        let r += [' - '.maker.name]
        for [k, V] in sort(copy(items(maker)))
            if k !=# 'name' && k !=# 'ft' && k !~# '^_'
                if !has_key(maker_defaults, k)
                            \ || type(V) != type(maker_defaults[k])
                            \ || V !=# maker_defaults[k]
                    let r += ['   - '.k.': '.string(V)]
                endif
            endif
            unlet V  " vim73
        endfor

        let issues = neomake#debug#validate_maker(maker)
        if !empty(issues)
            for type in sort(copy(keys(issues)))
                let items = issues[type]
                if !empty(items)
                    let r += ['   - '.toupper(type) . ':']
                    for issue in items
                        let r += ['     - ' . issue]
                    endfor
                endif
            endfor
        endif
    endfor
    return r
endfunction

function! neomake#debug#display_info(...) abort
    let bang = a:0 ? a:1 : 0
    let lines = neomake#debug#_get_info_lines()
    if bang
        try
            call setreg('+', join(lines, "\n"), 'l')
        catch
            call neomake#utils#ErrorMessage(printf(
                        \ 'Could not set clipboard: %s.', v:exception))
            return
        endtry
        echom 'Copied Neomake info to clipboard ("+).'
    else
        echon join(lines, "\n")
    endif
endfunction

function! neomake#debug#_get_info_lines() abort
    let r = []
    let ft = &filetype
    if &verbose
        let r += ['#### Neomake debug information']
        let r += ['']
        let r += ['Async support: '.neomake#has_async_support()]
        let r += ['Current filetype: '.ft]
        let r += ['Windows: '.neomake#utils#IsRunningWindows()]
        let r += ['[shell, shellcmdflag, shellslash]:' . string([&shell, &shellcmdflag, &shellslash])]
    else
        let r += ['#### Neomake information (use ":verbose NeomakeInfo" for extra output)']
    endif
    let r += ['']
    let r += ['##### Enabled makers']
    let r += ['']
    let r += ['For the current filetype ("'.ft.'", used with :Neomake):']
    let r += s:get_maker_info(ft)
    if empty(ft)
        let r += ['NOTE: the current buffer does not have a filetype.']
    else
        let conf_ft = neomake#utils#get_ft_confname(ft)
        let r += ['NOTE: you can define g:neomake_'.conf_ft.'_enabled_makers'
                    \ .' to configure it (or b:neomake_'.conf_ft.'_enabled_makers).']
    endif
    let r += ['']
    let r += ['Default maker settings:']
    for [k, v] in items(neomake#config#get('maker_defaults'))
        let r += [' - '.k.': '.string(v)]
        unlet! v  " Fix variable type mismatch with Vim 7.3.
    endfor
    let r += ['']
    let r += ['For the project (used with :Neomake!):']
    let r += s:get_maker_info()
    let r += ['NOTE: you can define g:neomake_enabled_makers to configure it.']
    let r += ['']
    let r += ['##### Settings']
    let r += ['']
    let r += ['###### New-style (dict, overrides old-style)']
    let r += ['']
    let r += ['```']

    function! s:pprint(d, ...) abort
        if type(a:d) != type({})
            return string(a:d)
        endif
        let indent = a:0 ? a:1 : ''
        if empty(a:d)
            return '{}'
        endif
        let r = "{\n"
        for [k, v] in items(a:d)
            let r .= indent.'  ' . string(k).': '.s:pprint(v, indent . '  ').",\n"
        endfor
        let r .= indent.'}'
        return r
    endfunction
    let r += ['g:neomake: '.(exists('g:neomake') ? s:pprint(g:neomake) : 'unset')]
    let r += ['b:neomake: '.(exists('b:neomake') ? s:pprint(b:neomake) : 'unset')]
    let r += ['```']
    let r += ['']
    let r += ['###### Old-style']
    let r += ['']
    let r += ['```']
    for [k, V] in sort(items(filter(copy(g:), "v:key =~# '^neomake_'")))
        let r += ['g:'.k.' = '.string(V)]
        unlet! V  " Fix variable type mismatch with Vim 7.3.
    endfor
    let r += ['']
    let r += ['```']
    let r += split(neomake#utils#redir('verb set makeprg?'), '\n')
    if &verbose
        let r += ["\n"]
        let r += ['#### :version']
        let r += ['']
        let r += ['```']
        let r += split(neomake#utils#redir('version'), '\n')
        let r += ['```']
        let r += ['']
        let r += ['#### :messages']
        let r += ['']
        let r += ['```']
        let r += split(neomake#utils#redir('messages'), '\n')
        let r += ['```']
    endif
    return r
endfunction
