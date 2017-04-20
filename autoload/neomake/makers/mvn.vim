" vim: ts=4 sw=4 et

function! neomake#makers#mvn#mvn()
    return {
         \ 'exe': 'mvn',
         \ 'args': ['install'],
         \ 'remove_invalid_entries' : 1,
         \ 'postprocess': function('neomake#makers#mvn#InvalidDuplicates'),
         \ 'errorformat':
           \ '%E[%tRROR]\ %f:[%l]\ %m,' .
           \ '%E[%tRROR]\ %f:[%l\,%v]\ %m,' .
           \ '%C\ %s:\ %m,' .
           \ '%C[ERROR]\ %s:\ %m,' .
           \ '%-G%.%#'
         \ }
endfunction

function! neomake#makers#mvn#InvalidDuplicates(entry) abort
    let entry = a:entry
    let text = entry.text
    let job = neomake#GetJobs()[entry.job_id]

    if !has_key(job, 'lines')
        let job.lines = []
    endif

    if index(job.lines, text) == -1
        call add(job.lines, text)
    else
        let entry.valid = 0
    endif
endfunction
