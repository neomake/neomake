" vim: ts=4 sw=4 et

function! neomake#makers#ft#purescript#EnabledMakers()
  return ['pulp']
endfunction

function! neomake#makers#ft#purescript#pulp()
    return {
        \ 'exe': 'pulp',
        \ 'args': ['build', '--no-psa', '--json-errors'],
        \ 'errorformat': '%t:%f:%l:%c:%n:%m',
        \ 'buffer_output': 1,
        \ 'append_file': 0,
        \ 'preprocess': function("ParsePulp"),
        \ 'postprocess': function("MarkStyleWarnings")
        \ }
endfunction

function! MarkStyleWarnings(entry)
        if a:entry.type == 'F'
            let a:entry.type = 'E'
            let a:entry.subtype = 'Style'
        endif
        if a:entry.type == 'V'
            let a:entry.type = 'W'
            let a:entry.subtype = 'Style'
        endif
endfunction

function! s:error(str)
  if exists('syntastic#log#error')
    let logger = function('syntastic#log#error')
  elseif exists('neomake#utils#ErrorMessage')
    let logger = function('neomake#utils#ErrorMessage')
  endif
  echom a:str
  if exists("logger")
    call logger(a:str)
  endif
endfunction

function! ParsePulp(lines)
  let out = []
  let str = join(a:lines, "")
  " echom a:line
  " let str = a:line

  if !exists('g:psc_ide_suggestions')
    let g:psc_ide_suggestions = {}
  endif

  "We need at least {"warnings":[],"errors":[]}
   if len(str) < 20 || str !~# '{' || str !~# '}'
     return out
   endif

  let matched = matchlist(str, '{.*}')

  if len(matched) > 0
    let decoded = s:_decode_JSON(matched[0])
  else
    call s:error('checker purescript/pulp: unrecognized error format 1: ' . str)
    return out
  endif
  
  let i = 0

  if type(decoded) == type({}) && type(decoded["warnings"]) == type([]) && type(decoded["errors"])
    for e in decoded['warnings']
      try
        call s:addEntry(out, 0, i, e)
        let i = i + 1
      catch /\m^Vim\%((\a\+)\)\=:E716/
        call s:error('checker purescript/pulp: unrecognized error format 2: ' . str)
        let out = []
        break
      endtry
    endfor
    for e in decoded['errors']
      try
        call s:addEntry(out, 1, i, e)
        let i = i + 1
      catch /\m^Vim\%((\a\+)\)\=:E716/
        call s:error('checker purescript/pulp: unrecognized error format 3: ' . str)
        let out = []
        break
      endtry
    endfor
  else
    call s:error('checker purescript/pulp: unrecognized error format 4: ' . str)
  endif
  return out
endfunction

function! s:addEntry(out, err, index, e)
  let hasSuggestion = exists("a:e.suggestion") && type(a:e.suggestion) == type({}) &&
                    \ exists("a:e.position") && type(a:e.position) == type({})
  let isError = a:err == 1
  let letter = isError ? (hasSuggestion ? 'F' : 'E') : (hasSuggestion ? 'V' : 'W')
  let startL = (exists("a:e.position") && type(a:e.position) == type({})) ? a:e.position.startLine : 1
  let startC = (exists("a:e.position") && type(a:e.position) == type({})) ? a:e.position.startColumn : 1
  let msg = join([letter, 
                \ a:e.filename, 
                \ startL,
                \ startC,
                \ string(a:index), 
                \ s:cleanupMessage(a:e.message)], ":")

  call add(a:out, msg)

  if hasSuggestion
    call s:addSuggestion(a:index, a:e)
  endif
endfunction

function! s:addSuggestion(i, e)
  if !exists('g:psc_ide_suggestions')
    return
  endif

  let sugg = {'startLine':   a:e['position']['startLine'], 
             \'startColumn': a:e['position']['startColumn'], 
             \'endLine':     a:e['position']['endLine'], 
             \'endColumn':   a:e['position']['endColumn'], 
             \'replacement': a:e['suggestion']['replacement']}

   let g:psc_ide_suggestions[string(a:i)] = sugg
endfunction

function! s:cleanupMessage(str)
    let transformations = [ ['\s*\n\+\s*', ' '], ['(\s', '('], ['\s)', ')'], ['\s\,', ','] ]
    let out = a:str
    for t in transformations
        let out = substitute(out, t[0], t[1], 'g')
    endfor
    return out
endfunction

function! s:_decode_JSON(json) abort
    if a:json ==# ''
        return []
    endif

    if substitute(a:json, '\v\"%(\\.|[^"\\])*\"|true|false|null|[+-]?\d+%(\.\d+%([Ee][+-]?\d+)?)?', '', 'g') !~# "[^,:{}[\\] \t]"
        " JSON artifacts
        let true = 1
        let false = 0
        let null = ''

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
endfunction 
