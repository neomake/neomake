" vim: ts=4 sw=4 et

function! neomake#makers#ft#d#EnabledMakers()
    "dmd, ldmd, and gdmd all share a common CLI.
    "Ordered in efficiency of compiler
    let l:makers = []
    if neomake#utils#Exists('dmd')
        call add(l:makers, 'dmd')
    elseif neomake#utils#Exists('ldmd')
        call add(l:makers, 'ldmd')
    elseif neomake#utils#Exists('gdmd')
        call add(l:makers, 'gdmd')
    endif
    return l:makers
endfunction

function! s:UpdateDub()
    "Add dub directories
    let l:tmp_file = findfile("dub.json", ".;")
    "dmd happily accepts an empty import string.
    let l:dub_incs = "-I"
    if neomake#utils#Exists('dub') && !empty(l:tmp_file)
        let l:tmp_dir = fnamemodify(l:tmp_file,':p:h')
        "Get the dub dependencies from the dub describe command.
        "vim doesn't seem to play nice with newlines
        let l:dub = eval(substitute(system("dub describe --annotate --root=" . tmp_dir)
                    \ ,'\v[\n\r]','','g'))
        let l:tmp_arr = []
        "Extract the packages from the dictionary
        for l:package in l:dub.packages
            let l:path = l:package.path
            for l:importPath in l:package.importPaths
                call add(tmp_arr, l:path . l:importPath)
            endfor
        endfor
        let l:dub_incs .= join(tmp_arr, ":")
    endif
    return l:dub_incs
endfunction

function! neomake#makers#ft#d#dmd()
    let l:args = ['-c', '-o-', s:UpdateDub()]
    "Updating dub paths each make might be slow?
    if exists("g:neomake_d_dmd_args_conf")
        call add(l:args, '-conf=' . expand(g:neomake_d_dmd_args_conf))
    else "Try some sensible defaults.
        let l:args += ['-wi', '-debug']
    endif
    return {
        \ 'args': l:args,
        \ 'errorformat':
        \     '%-G%f:%s:,%f(%l): %m,' .
        \     '%f:%l: %m',
        \ }
endfunction

function! neomake#makers#ft#d#ldmd()
    return neomake#makers#ft#d#dmd()
endfunction

function! neomake#makers#ft#d#gdmd()
    return neomake#makers#ft#d#dmd()
endfunction
