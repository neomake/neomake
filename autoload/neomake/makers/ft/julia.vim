function! neomake#makers#ft#julia#EnabledMakers() abort
    return ['julia']
endfunction

function! neomake#makers#ft#julia#julia() abort
    return {
\       'errorformat': '%f:%l %t%*[^ ] %m',
\       'args': ['-e', '
\           try
\               using Lint
\           catch
\               println("$(basename(ARGS[1])):1 E999 Install Lint.jl: Pkg.add(\\"Lint\\")");
\               exit(1)
\           end;
\           r = lintfile(ARGS[1]);
\           if !isempty(r)
\               display(r);
\               exit(1)
\           end
\       ']
\   }
endfunction
