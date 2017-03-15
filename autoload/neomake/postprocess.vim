" Generic postprocessor to add `length` to `a:entry`.
" The pattern can be overridden on `self`, and should adhere to this:
"  - the matched word should be returned as the whole match (you can use \zs
"    and \ze).
"  - enclosing patterns should be returned as \1 and \2, where \1 is used as
"    offset when the first entry did not match.
" See tests/postprocess.vader for tests/examples.
function! neomake#postprocess#GenericLengthPostprocess(entry) abort dict
  if a:entry.bufnr == bufnr('%') && a:entry.lnum > 0 && a:entry.col
    let pattern = get(self, 'pattern', "\\v([\"'])\\zs[^\\1]{-}\\ze(\\1)")
    let start = 0
    let best = 0
    while 1
      let text = a:entry.text
      let pos = matchstrpos(a:entry.text, pattern, start)
      let t = a:entry.text
      if pos[1] == -1
        break
      endif
      let m = matchlist(a:entry.text, pattern, start)
      if empty(m)
        break
      endif
      let l = len(m[0])
      if l > best
        " AssertEqual l, pos[2]-pos[1]
        " Ensure that the text is there.
        if getline(a:entry.lnum)[a:entry.col-1 : a:entry.col-2+l] == m[0]
          let best = l
        endif
      endif
      let start += pos[2] + len(m[2])
    endwhile
    if best
      let a:entry.length = best
    endif
  endif
endfunction

" vim: ts=2 sw=2 et
