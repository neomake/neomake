" Keep track of for what maker.exe an error was thrown.
let s:exe_error_thrown = {}

function! neomake#core#create_jobs(options, makers) abort
    let args = [a:options, a:makers]
    if a:options.file_mode
        let args += [a:options.ft]
    endif
    let jobs = call('s:bind_makers_for_job', args)
    return jobs
endfunction

" Map/bind a:makers to a list of job options, using a:options.
function! s:bind_makers_for_job(options, makers, ...) abort
    let r = []
    for maker in a:makers
        let options = copy(a:options)
        try
            " Call .fn function in maker object, if any.
            if has_key(maker, 'fn')
                " TODO: Allow to throw and/or return 0 to abort/skip?!
                let returned_maker = call(maker.fn, [options], maker)
                if returned_maker isnot# 0
                    " This conditional assignment allows to both return a copy
                    " (factory), while also can be used as a init method.
                    let maker = returned_maker
                endif
            endif

            if has_key(maker, '_bind_args')
                call maker._bind_args()
                if type(maker.exe) != type('')
                    let error = printf('Non-string given for executable of maker %s: type %s.',
                                \ maker.name, type(maker.exe))
                    if !get(maker, 'auto_enabled', 0)
                        call neomake#utils#ErrorMessage(error, options)
                    else
                        call neomake#utils#DebugMessage(error, options)
                    endif
                    continue
                endif
                if !executable(maker.exe)
                    if !get(maker, 'auto_enabled', 0)
                        let error = printf('Exe (%s) of maker %s is not executable.', maker.exe, maker.name)
                        if !has_key(s:exe_error_thrown, maker.exe)
                            let s:exe_error_thrown[maker.exe] = 1
                            call neomake#utils#ErrorMessage(error, options)
                        else
                            call neomake#utils#DebugMessage(error, options)
                        endif
                    else
                        call neomake#utils#DebugMessage(printf(
                                    \ 'Exe (%s) of auto-configured maker %s is not executable, skipping.', maker.exe, maker.name), options)
                    endif
                    continue
                endif
            endif

        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '').'.'
            call neomake#utils#ErrorMessage(error, {'make_id': options.make_id})
            continue
        endtry
        let options.maker = maker
        let r += [options]
    endfor
    return r
endfunction
