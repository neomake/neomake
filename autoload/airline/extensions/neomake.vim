" vim: ts=4 sw=4 et

if exists('g:neomake_airline') && g:neomake_airline == 0
    finish
endif

let s:spc = g:airline_symbols.space

function! airline#extensions#neomake#apply(...)
    let w:airline_section_warning = get(w:, 'airline_section_warning', g:airline_section_warning)
    let w:airline_section_warning .= s:spc.'%{neomake#statusline#LoclistStatus()}'
endfunction

function! airline#extensions#neomake#init(ext)
    call airline#parts#define_raw('neomake', '%{neomake#statusline#LoclistStatus()}')
    call a:ext.add_statusline_func('airline#extensions#neomake#apply')
endfunction
