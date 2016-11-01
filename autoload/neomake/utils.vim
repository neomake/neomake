" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:level_to_name = {
            \ 0: 'error',
            \ 1: 'quiet',
            \ 2: 'verb ',
            \ 3: 'debug',
            \ }

if has('reltime')
    let s:reltime_start = reltime()
endif
function! s:timestr() abort
    if exists('s:reltime_start')
        let cur_time = split(split(reltimestr(reltime(s:reltime_start)))[0], '\.')
        return cur_time[0].'.'.cur_time[1][0:2]
    endif
    return strftime('%H:%M:%S')
endfunction

function! neomake#utils#LogMessage(level, msg, ...) abort
    let verbose = get(g:, 'neomake_verbose', 1)
    let logfile = get(g:, 'neomake_logfile')

    if exists(':Log') != 2 && verbose < a:level && logfile is ''
        return
    endif

    if a:0
        let jobinfo = a:1
        if has_key(jobinfo, 'id')
            let msg = printf('[%d.%d] %s', jobinfo.make_id, jobinfo.id, a:msg)
        else
            let msg = printf('[%d] %s', jobinfo.make_id, a:msg)
        endif
    else
        let jobinfo = {}
        let msg = a:msg
    endif

    if exists('*vader#log')
        " Log is defined during Vader tests.
        let test_msg = '['.s:level_to_name[a:level].'] ['.s:timestr().']: '.msg
        call vader#log(test_msg)
        let g:neomake_test_messages += [[a:level, a:msg, jobinfo]]
    endif

    if verbose >= a:level
        redraw
        if a:level ==# 0
            echohl ErrorMsg
        endif
        if verbose > 2
            echom 'Neomake ['.s:timestr().']: '.msg
        else
            echom 'Neomake: '.msg
        endif
        if a:level ==# 0
            echohl None
        endif
    endif
    if type(logfile) ==# type('') && len(logfile)
        let date = strftime('%Y-%m-%dT%H:%M:%S%z')
        call writefile(['['.date.' @'.s:timestr().', '.s:level_to_name[a:level].'] '.msg], logfile, 'a')
    endif
endfunction

function! neomake#utils#ErrorMessage(...) abort
    call call('neomake#utils#LogMessage', [0] + a:000)
endfunction

function! neomake#utils#QuietMessage(...) abort
    call call('neomake#utils#LogMessage', [1] + a:000)
endfunction

function! neomake#utils#LoudMessage(...) abort
    call call('neomake#utils#LogMessage', [2] + a:000)
endfunction

function! neomake#utils#DebugMessage(...) abort
    call call('neomake#utils#LogMessage', [3] + a:000)
endfunction

function! neomake#utils#Stringify(obj) abort
    if type(a:obj) == type([])
        let ls = map(copy(a:obj), 'neomake#utils#Stringify(v:val)')
        return '['.join(ls, ', ').']'
    elseif type(a:obj) == type({})
        let ls = []
        for key in keys(a:obj)
            call add(ls, key.': '.neomake#utils#Stringify(a:obj[key]))
        endfor
        return '{'.join(ls, ', ').'}'
    else
        return ''.a:obj
    endif
endfunction

function! neomake#utils#DebugObject(msg, obj) abort
    call neomake#utils#DebugMessage(a:msg.' '.neomake#utils#Stringify(a:obj))
endfunction

" This comes straight out of syntastic.
"print as much of a:msg as possible without "Press Enter" prompt appearing
function! neomake#utils#WideMessage(msg) abort " {{{2
    let old_ruler = &ruler
    let old_showcmd = &showcmd

    "This is here because it is possible for some error messages to
    "begin with \n which will cause a "press enter" prompt.
    let msg = substitute(a:msg, "\n", '', 'g')

    "convert tabs to spaces so that the tabs count towards the window
    "width as the proper amount of characters
    let chunks = split(msg, "\t", 1)
    let msg = join(map(chunks[:-2], "v:val . repeat(' ', &tabstop - strwidth(v:val) % &tabstop)"), '') . chunks[-1]
    let msg = strpart(msg, 0, &columns - 1)

    set noruler noshowcmd
    redraw

    call neomake#utils#DebugMessage('WideMessage echo '.msg)
    echo msg

    let &ruler = old_ruler
    let &showcmd = old_showcmd
endfunction " }}}2

" This comes straight out of syntastic.
function! neomake#utils#IsRunningWindows() abort
    return has('win32') || has('win64')
endfunction

" This comes straight out of syntastic.
function! neomake#utils#DevNull() abort
    if neomake#utils#IsRunningWindows()
        return 'NUL'
    endif
    return '/dev/null'
endfunction

function! neomake#utils#Exists(exe) abort
    " DEPRECATED: just use executable() directly.
    return executable(a:exe)
endfunction

function! neomake#utils#Random() abort
    call neomake#utils#DebugMessage('Calling neomake#utils#Random')
    if neomake#utils#IsRunningWindows()
        let cmd = 'Echo %RANDOM%'
    else
        let cmd = 'echo $RANDOM'
    endif
    let answer = 0 + system(cmd)
    if v:shell_error
        " If complaints come up about this, consider using python
        throw "Can't generate random number for this platform"
    endif
    return answer
endfunction

function! neomake#utils#MakerFromCommand(command) abort
    " XXX: use neomake#utils#ExpandArgs and/or remove it.
    "      Expansion should happen later already!
    let command = substitute(a:command, '%\(:[a-z]\)*',
                           \ '\=expand(submatch(0))', 'g')
    return {
        \ 'exe': &shell,
        \ 'args': [&shellcmdflag, command],
        \ 'remove_invalid_entries': 0,
        \ }
endfunction

let s:available_makers = {}
function! neomake#utils#MakerIsAvailable(ft, maker_name) abort
    if a:maker_name ==# 'makeprg'
        " makeprg refers to the actual makeprg, which we don't need to check
        " for our purposes
        return 1
    endif
    if !has_key(s:available_makers, a:maker_name)
        let maker = neomake#GetMaker(a:maker_name, a:ft)
        let s:available_makers[a:maker_name] = executable(maker.exe)
    endif
    return s:available_makers[a:maker_name]
endfunction

function! neomake#utils#AvailableMakers(ft, makers) abort
    return filter(copy(a:makers), 'neomake#utils#MakerIsAvailable(a:ft, v:val)')
endfunction

function! neomake#utils#GetSupersetOf(ft) abort
    try
        return eval('neomake#makers#ft#' . a:ft . '#SupersetOf()')
    catch /^Vim\%((\a\+)\)\=:E117/
        return ''
    endtry
endfunction

" Attempt to get list of filetypes in order of most specific to least specific.
function! neomake#utils#GetSortedFiletypes(ft) abort
    function! CompareFiletypes(ft1, ft2) abort
        if neomake#utils#GetSupersetOf(a:ft1) ==# a:ft2
            return -1
        elseif neomake#utils#GetSupersetOf(a:ft2) ==# a:ft1
            return 1
        else
            return 0
        endif
    endfunction

    return sort(split(a:ft, '\.'), function('CompareFiletypes'))
endfunction

" Get a setting by key, based on filetypes, from the buffer or global
" namespace, defaulting to default.
function! neomake#utils#GetSetting(key, maker, default, fts, bufnr) abort
  if has_key(a:maker, 'name')
    if len(a:fts)
      for ft in a:fts
        " Look through the neomake setting override vars for a filetype maker,
        " like neomake_scss_sasslint_exe (should be a string), and 
        " neomake_scss_sasslint_args (should be a list)
        let config_var = 'neomake_'.ft.'_'.a:maker.name.'_'.a:key
        if has_key(g:, config_var)
              \ || !empty(getbufvar(a:bufnr, config_var))
          break
        endif
      endfor
    else
      " Following this, we're checking the neomake overrides for global makers
      let config_var = 'neomake_'.a:maker.name.'_'.a:key
    endif

    if !empty(getbufvar(a:bufnr, config_var))
      return copy(getbufvar(a:bufnr, config_var))
    elseif has_key(g:, config_var)
      return copy(get(g:, config_var))
    endif
  endif
  if has_key(a:maker, a:key)
    return a:maker[a:key]
  endif
  " Look for 'neomake_'.key in the buffer and global namespace.
  let bufvar = getbufvar(a:bufnr, 'neomake_'.a:key)
  if !empty(bufvar)
      return bufvar
  endif
  let var = get(g:, 'neomake_'.a:key)
  if !empty(var)
      return var
  endif
  return a:default
endfunction

" Get property from highlighting group.
function! neomake#utils#GetHighlight(group, what) abort
  let reverse = synIDattr(synIDtrans(hlID(a:group)), 'reverse')
  let what = a:what
  if reverse
    let what = neomake#utils#ReverseSynIDattr(what)
  endif
  if what[-1:] ==# '#'
      let val = synIDattr(synIDtrans(hlID(a:group)), what, 'gui')
  else
      let val = synIDattr(synIDtrans(hlID(a:group)), what, 'cterm')
  endif
  if empty(val) || val == -1
    let val = 'NONE'
  endif
  return val
endfunction

function! neomake#utils#ReverseSynIDattr(attr) abort
  if a:attr ==# 'fg'
    return 'bg'
  elseif a:attr ==# 'bg'
    return 'fg'
  elseif a:attr ==# 'fg#'
    return 'bg#'
  elseif a:attr ==# 'bg#'
    return 'fg#'
  endif
  return a:attr
endfunction

function! neomake#utils#CompressWhitespace(entry) abort
    let text = a:entry.text
    let text = substitute(text, "\001", '', 'g')
    let text = substitute(text, '\r\?\n', ' ', 'g')
    let text = substitute(text, '\m\s\{2,}', ' ', 'g')
    let text = substitute(text, '\m^\s\+', '', '')
    let text = substitute(text, '\m\s\+$', '', '')
    let a:entry.text = text
endfunction

function! neomake#utils#redir(cmd) abort
    if exists('*execute') && has('nvim')
        " NOTE: require Neovim, since Vim has at least an issue when using
        "       this in a :command-completion function.
        "       Ref: https://github.com/neomake/neomake/issues/650.
        return execute(a:cmd)
    endif
    if type(a:cmd) == type([])
        let r = ''
        for cmd in a:cmd
            let r .= neomake#utils#redir(cmd)
        endfor
        return r
    endif
    redir => neomake_redir
    try
        silent exe a:cmd
    finally
        redir END
    endtry
    return neomake_redir
endfunction

function! neomake#utils#ExpandArgs(args) abort
    " Only expand those args that start with \ and a single %
    call map(a:args, "v:val =~# '\\(^\\\\\\|^%$\\|^%[^%]\\)' ? expand(v:val) : v:val")
endfunction

function! neomake#utils#ParseSemanticVersion(version_string) abort
    let l:parser = copy(a:)
    let l:parser.parsed = {
                \ 'major': 0,
                \ 'minor': 0,
                \ 'patch': 0,
                \ 'stage': [],
                \ 'metadata': []
                \ }


    " A simple helper function for regex captures
    function! l:parser.Capture(regex) abort dict
        return '\(' . a:regex . '\)'
    endfunction

    function! l:parser.ParseIdentifier(identifier, convert) abort dict
        " Identifer must be non-empty
        if empty(a:identifier)
            return ''
        endif

        " If an identifier is all numeric, convert it to a number
        if a:convert && match(a:identifier, '\D') == -1
            " Numeric identifiers must not start with a leading 0
            return len(a:identifier) > 1 && strpart(a:identifier, 0, 1) ==# '0'
                        \ ? '' : str2nr(a:identifier)
        endif

        " Otherwise identifiers must be alphanumeric and can include a hyphen
        if match(a:identifier,  '\%(^[[:alnum:]-]\+\)$') == -1
            return ''
        endif

        return a:identifier
    endfunction

    function! l:parser.ParseBasic() abort dict
        " MAJOR.MINOR.PATCH
        " http://semver.org/#spec-item-2
        let l:regex = join(repeat([self.Capture('0\|[1-9]\d*')], 3), '.')

        " Pre-release version
        " http://semver.org/#spec-item-9
        let l:regex .= self.Capture('-[^+]*') . '\?'

        " Build metadata
        " http://semver.org/#spec-item-10
        let l:regex .= self.Capture('+.*') . '\?'

        let self.matches = matchlist(self.version_string, l:regex)
        if empty(self.matches)
            " Must include MAJOR, MINOR, and PATCH to be valid
            return 0
        endif

        let l:parsed = self.parsed
        let l:parsed.major = str2nr(self.matches[1])
        let l:parsed.minor = str2nr(self.matches[2])
        let l:parsed.patch = str2nr(self.matches[3])
        return 1
    endfunction

    function! l:parser.ParseAdditional(key) abort dict
        if a:key ==# 'stage'
            let l:index = 4
            let l:prefix = '-'
            let l:convert = 1
        elseif a:key ==# 'metadata'
            let l:index = 5
            let l:prefix = '+'
            let l:convert = 0
        else
            return 0
        endif

        let l:identifiers_string = self.matches[l:index]
        if strpart(l:identifiers_string, 0, 1) ==# l:prefix
            let l:identifiers_string = strpart(l:identifiers_string, 1)
            let l:identifiers_list = split(l:identifiers_string, '\.')

            " Parse the identifiers
            call map(l:identifiers_list, 'self.ParseIdentifier(v:val, l:convert)')

            " Ensure all indentifiers are valid
            if empty(l:identifiers_list) || match(l:identifiers_list, '^$') > -1
                " Identifiers must be non-empty
                return 0
            endif

            let self.parsed[a:key] = l:identifiers_list
        endif

        return 1
    endfunction

    if !l:parser.ParseBasic()
        call neomake#utils#DebugMessage('Invalid semantic version string "'.a:version_string.'"')
        return {}
    endif

    if !l:parser.ParseAdditional('stage')
        call neomake#utils#DebugMessage('Invalid semantic version pre-release string "'.a:version_string.'"')
        return {}
    endif

    if !l:parser.ParseAdditional('metadata')
        call neomake#utils#DebugMessage('Invalid semantic version metadata string "'.a:version_string.'"')
        return {}
    endif

    return l:parser.parsed
endfunction

function! neomake#utils#CompareSemanticVersions(ver1, ver2) abort
    let l:ver1 = neomake#utils#ParseSemanticVersion(a:ver1)
    let l:ver2 = neomake#utils#ParseSemanticVersion(a:ver2)

    " Both must be valid semantic versions
    if l:ver1 == {} || l:ver2 == {}
        return 0
    endif

    " Semantic versioning precendence
    " http://semver.org/#spec-item-11

    " Precedence is determined by the first difference when comparing each of
    " these identifiers from left to right as follows: Major, minor, and patch
    " versions are always compared numerically. Example: 1.0.0 < 2.0.0 < 2.1.0
    " < 2.1.1.
    if l:ver1.major != l:ver2.major
        return l:ver1.major < l:ver2.major ? -1 : 1
    endif

    if l:ver1.minor != l:ver2.minor
        return l:ver1.minor < l:ver2.minor ? -1 : 1
    endif

    if l:ver1.patch != l:ver2.patch
        return l:ver1.patch < l:ver2.patch ? -1 : 1
    endif

    " When major, minor, and patch are equal, a pre-release version has lower
    " precedence than a normal version. Example: 1.0.0-alpha < 1.0.0.
    if empty(l:ver1.stage) != empty(l:ver2.stage)
        return empty(l:ver2.stage) ? -1 : 1
    endif

    " Precedence for two pre-release versions with the same major, minor, and
    " patch version MUST be determined by comparing each dot separated
    " identifier from left to right until a difference is found
    "
    " Example: 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta <
    " 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0.
    let l:ver1len = len(l:ver1.stage)
    let l:ver2len = len(l:ver2.stage)
    for i in range(min([l:ver1len, l:ver2len]))
        let l:val1 = l:ver1.stage[i]
        let l:val2 = l:ver2.stage[i]
        let l:numeric1 = type(l:val1) == type(0)
        let l:numeric2 = type(l:val2) == type(0)

        " Numeric identifiers always have lower precedence than non-numeric
        " identifiers.
        if l:numeric1 != l:numeric2
            return l:numeric1 ? -1 : 1
        endif

        " identifiers consisting of only digits are compared numerically
        if l:numeric1
            if l:val1 < l:val2
                return -1
            elseif l:val1 > l:val2
                return 1
            endif
        endif

        " identifiers with letters or hyphens are compared lexically in ASCII
        " sort order.
        if !l:numeric1
            if l:val1 <# l:val2
                return -1
            elseif l:val1 ># l:val2
                return 1
            endif
        endif
    endfor

    " A larger set of pre-release fields has a higher precedence than a
    " smaller set, if all of the preceding identifiers are equal.
    return l:ver1len > l:ver2len ? 1 : l:ver2len > l:ver1len ? -1 : 0
endfunction
