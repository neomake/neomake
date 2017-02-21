function! neomake#postprocess#GenericLengthPostprocess(entry) abort dict
  if a:entry.bufnr == bufnr('%') && a:entry.lnum > 0 && a:entry.col
    let pattern = get(self, 'pattern', "\\v([\"'])\\zs[^\\1]+\\ze\\1")
    let m = matchstr(a:entry.text, pattern)
    let l = len(m)
    if l
      " Ensure that the text is there.
      if getline(a:entry.lnum)[a:entry.col-1 : a:entry.col-2+l] == m
        let a:entry.length = l
      endif
    endif
  endif
endfunction

" vim: ts=2 sw=2 et
