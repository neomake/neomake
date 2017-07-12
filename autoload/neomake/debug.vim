function! neomake#debug#validate_maker(maker) abort
    let issues = {'errors': [], 'warnings': []}

    if has_key(a:maker, 'process_output')
        if has_key(a:maker, 'mapexpr')
            let issues.warnings += ['maker has mapexpr, but only process_output will be used.']
        endif
        if has_key(a:maker, 'postprocess')
            let issues.warnings += ['maker has postprocess, but only process_output will be used.']
        endif
    endif

    if !executable(a:maker.exe)
        let t = a:maker.auto_enabled ? 'warnings' : 'errors'
        let issues[t] += [printf("maker's exe (%s) is not executable.", a:maker.exe)]
    endif

    return issues
endfunction
