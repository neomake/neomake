let s:defined_fg_hl_groups = 0

" Setup base highlight groups for foreground attributes.
function! neomake#setup#highlight#define_fg_highlight_groups() abort
    for [group, fg_from] in items({
                \ 'NeomakeFgError': ['Error', 'ctermfg=1 guifg=Red'],
                \ 'NeomakeFgWarning': ['Todo', 'ctermfg=3 guifg=Yellow'],
                \ 'NeomakeFgInfo': ['Question', 'ctermfg=6 guifg=Cyan'],
                \ 'NeomakeFgMessage': ['ModeMsg', 'ctermfg=4 guifg=Blue'],
                \ })
        let hi = neomake#setup#highlight#get_hi_for_fg(fg_from[0])
        if empty(hi)
            let hi = fg_from[1]
        endif
        exe printf('hi %s %s', group, hi)
    endfor
endfunction

" Get accent/relevant color from a highlight group.
" Uses heuristics to get e.g. the red from "Error", where it might either be
" via its background or foreground.
function! neomake#setup#highlight#get_hi_for_fg(from) abort
    if index(['0', '7', '8', '15', 'NONE'], neomake#utils#GetHighlight(a:from, 'fg')) != -1
        " Use bg if fg is black/white.
        let use = 'bg'
    else
        let use = 'fg'
    endif
    let r = []
    " TODO: keep cterm and gui attributes?
    let ctermfg = neomake#utils#GetHighlight(a:from, use)
    if ctermfg !=# 'NONE'
        call add(r, 'ctermfg='.ctermfg)
    endif
    let guifg = neomake#utils#GetHighlight(a:from, use.'#')
    if guifg !=# 'NONE'
        call add(r, 'guifg='.guifg)
    endif
    return join(r, ' ')
endfunction

" Helper function to define default highlight for a:group (e.g.
" "Neomake%sSign"), using fg from another highlight, abd given background.
function! neomake#setup#highlight#define_derived_highlights(group_format, bg) abort
    if !s:defined_fg_hl_groups
        " Only define this once on demand, gets done for ColorScheme always.
        call neomake#setup#highlight#define_fg_highlight_groups()
        let s:defined_fg_hl_groups = 1
    endif
    for [type, fg_from] in items({
                \ 'Error': 'NeomakeFgError',
                \ 'Warning': 'NeomakeFgWarning',
                \ 'Info': 'NeomakeFgInfo',
                \ 'Message': 'NeomakeFgMessage'
                \ })
        let group = printf(a:group_format, type)
        call s:define_derived_highlight_group(group, fg_from, a:bg)
    endfo
endfunction

function! s:define_derived_highlight_group(group, fg_from, bg) abort
    let [ctermbg, guibg] = a:bg
    let bg = 'ctermbg='.ctermbg.' guibg='.guibg

    " NOTE: fg falls back to "Normal" always, not bg (for e.g. "SignColumn")
    " inbetween.
    " Ensure that we're not using bg as fg (as with gotham
    " colorscheme, issue https://github.com/neomake/neomake/pull/659).
    let ctermfg = neomake#utils#GetHighlight(a:fg_from, 'fg')
    if ctermfg !=# 'NONE' && ctermfg ==# ctermbg
        let ctermfg = neomake#utils#GetHighlight(a:fg_from, 'bg')
    endif
    let guifg = neomake#utils#GetHighlight(a:fg_from, 'fg#')
    if guifg !=# 'NONE' && guifg ==# guibg
        let guifg = neomake#utils#GetHighlight(a:fg_from, 'bg#')
    endif

    exe 'hi '.a:group.'Default ctermfg='.ctermfg.' guifg='.guifg.' '.bg
    if !neomake#utils#highlight_is_defined(a:group)
        exe 'hi link '.a:group.' '.a:group.'Default'
    endif
endfunction

function! neomake#setup#highlight#define_highlights() abort
    call neomake#setup#highlight#define_fg_highlight_groups()

    if g:neomake_place_signs
        call neomake#signs#DefineHighlights()
    endif
    if get(g:, 'neomake_highlight_columns', 1)
                \ || get(g:, 'neomake_highlight_lines', 0)
        call neomake#highlights#DefineHighlights()
    endif
    call neomake#virtualtext#DefineHighlights()
endfunction

" vim: ts=4 sw=4 et
