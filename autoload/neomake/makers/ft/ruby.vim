" vim: ts=4 sw=4 et

function! neomake#makers#ft#ruby#EnabledMakers() abort
    return ['flog', 'mri', 'rubocop', 'reek', 'rubylint']
endfunction

function! neomake#makers#ft#ruby#rubocop() abort
    return {
        \ 'args': ['--format', 'emacs', '--force-exclusion', '--display-cop-names'],
        \ 'errorformat': '%f:%l:%c: %t: %m,%E%f:%l: %m',
        \ 'postprocess': function('neomake#makers#ft#ruby#RubocopEntryProcess'),
        \ 'output_stream': 'stdout',
        \ }
endfunction

function! neomake#makers#ft#ruby#RubocopEntryProcess(entry) abort
    if a:entry.type ==# 'F'  " Fatal error which prevented further processing
        let a:entry.type = 'E'
    elseif a:entry.type ==# 'E'  " Error for important programming issues
        let a:entry.type = 'E'
    elseif a:entry.type ==# 'W'  " Warning for stylistic or minor programming issues
        let a:entry.type = 'W'
    elseif a:entry.type ==# 'R'  " Refactor suggestion
        let a:entry.type = 'W'
    elseif a:entry.type ==# 'C'  " Convention violation
        let a:entry.type = 'I'
    endif
endfunction

function! neomake#makers#ft#ruby#rubylint() abort
    return {
        \ 'exe': 'ruby-lint',
        \ 'args': ['--presenter', 'syntastic'],
        \ 'errorformat': '%f:%t:%l:%c: %m',
        \ }
endfunction

function! neomake#makers#ft#ruby#mri() abort
    let errorformat = '%-G%\m%.%#warning: %\%%(possibly %\)%\?useless use of == in void context,'
    let errorformat .= '%-G%\%.%\%.%\%.%.%#,'
    let errorformat .=
        \ '%-GSyntax OK,'.
        \ '%E%f:%l: syntax error\, %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: warning: %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: %m,'.
        \ '%-C%.%#'

    return {
        \ 'exe': 'ruby',
        \ 'args': ['-c', '-T1', '-w'],
        \ 'errorformat': errorformat,
        \ 'output_stream': 'both',
        \ }
endfunction

function! neomake#makers#ft#ruby#jruby() abort
    let errorformat =
        \ '%-GSyntax OK for %f,'.
        \ '%ESyntaxError in %f:%l: syntax error\, %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: warning: %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: %m,'.
        \ '%-C%.%#'

    return {
        \ 'exe': 'jruby',
        \ 'args': ['-c', '-T1', '-w'],
        \ 'errorformat': errorformat
        \ }
endfunction

function! neomake#makers#ft#ruby#reek() abort
    return {
        \ 'args': ['--format', 'text', '--single-line'],
        \ 'errorformat': '%W%f:%l: %m',
        \ }
endfunction

function! neomake#makers#ft#ruby#flog() abort
    return {
        \ 'errorformat':
        \   '%W%m %f:%l-%c,' .
        \   '%-G\s%#,' .
        \   '%-G%.%#: flog total,' .
        \   '%-G%.%#: flog/method average,'
        \ }
endfunction

let g:neomake#makers#ft#ruby#project_root_files = ['Gemfile', 'Rakefile']

function! s:get_gemfile() abort
    let gemfile = neomake#config#get('ruby.gemfile')
    if gemfile isnot# g:neomake#config#undefined
        return gemfile
    endif

    let project_root = neomake#utils#get_project_root()
    if empty(project_root)
        let gemfile = findfile('Gemfile', '.;~')
    else
        let gemfile = project_root . neomake#utils#Slash() . 'Gemfile'
        if !filereadable(gemfile)
            let gemfile = ''
        endif
    endif

    call neomake#log#debug(
                \ printf('ruby: setting b:neomake.ruby.gemfile=%s', string(gemfile)),
                \ { 'bufnr': bufnr('%') })
    call neomake#config#set('b:ruby.gemfile', gemfile)
    return gemfile
endfunction

function! neomake#makers#ft#ruby#try_bundler(jobinfo) abort dict
    let gemfile = s:get_gemfile()
    if !empty(gemfile)
        let matcher = escape('v:val =~# "\v\s*gem\s+\S+' . self.exe . '"', '\')
        if !empty(filter(readfile(gemfile), matcher))
            call call('neomake#makers#ft#ruby#use_bundler', [a:jobinfo], self)
        endif
    endif
endfunction

function! neomake#makers#ft#ruby#use_bundler(jobinfo) abort dict
    let self.args = ['exec', self.exe] + self.args
    let self.exe = 'bundle'
endfunction
