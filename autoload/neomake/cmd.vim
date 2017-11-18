let s:last_completion = []
function! neomake#cmd#complete_makers(ArgLead, CmdLine, ...) abort
    if a:ArgLead =~# '[^A-Za-z0-9]'
        return []
    endif
    if a:CmdLine !~# '\s'
        " Just 'Neomake!' without following space.
        return [' ']
    endif

    let file_mode = a:CmdLine =~# '\v^(Neomake|NeomakeFile)\s'

    let compl_info = [bufnr('%'), &filetype, a:CmdLine]
    if empty(&filetype)
        let maker_names = neomake#GetProjectMakers()
    else
        let maker_names = neomake#GetMakers(&filetype)
        " TODO: exclude makers based on some property?!
        " call filter(makers, "get(v:val, 'uses_filename', 1) == file_mode")

        " Prefer (only) makers for the current filetype.
        if file_mode
            call filter(maker_names, "v:val =~? '^".a:ArgLead."'")
            if empty(maker_names) || s:last_completion == compl_info
                call extend(maker_names, neomake#GetProjectMakers())
            endif
        else
            call extend(maker_names, neomake#GetProjectMakers())
        endif
    endif

    " Only display executable makers.
    let makers = map(maker_names, 'neomake#GetMaker(v:val)')
    call filter(makers, "type(get(v:val, 'exe', 0)) != type('') || executable(v:val.exe)")
    let maker_names = map(makers, 'v:val.name')

    let s:last_completion = compl_info
    return filter(maker_names, "v:val =~? '^".a:ArgLead."'")
endfunction

function! neomake#cmd#complete_jobs(...) abort
    return join(map(neomake#GetJobs(), "v:val.id.': '.v:val.maker.name"), "\n")
endfunction
