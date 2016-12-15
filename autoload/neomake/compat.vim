" Function to wrap Compatibility across different (Neo)Vim versions.

if v:version >= 704
  function! neomake#compat#getbufvar(buf, key, def) abort
    return getbufvar(a:buf, a:key, a:def)
  endfunction
else
  function! neomake#compat#getbufvar(buf, key, def) abort
    return get(getbufvar(a:buf, ''), a:key, a:def)
  endfunction
endif
