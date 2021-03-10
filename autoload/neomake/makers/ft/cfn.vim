function! neomake#makers#ft#cfn#EnabledMakers() abort
    return ['cfnlint']
endfunction

function! neomake#makers#ft#cfn#cfnlint() abort
    return {
                \ 'exe': 'cfn-lint',
                \ 'args': ['--format', 'json', '--template'],
                \ 'process_output': function('neomake#makers#ft#cfn#CfnlintProcessOutput')
                \ }
endfunction

function! neomake#makers#ft#cfn#CfnlintProcessOutput(context) abort
    let entries = []

		let output = neomake#compat#json_decode(a:context['output'])

    for item in output
        let entry = {
                    \ 'filename': item.Filename,
                    \ 'text': item.Message,
                    \ 'lnum': item.Location.Start.LineNumber,
                    \ 'col': item.Location.Start.ColumnNumber,
                    \ 'type': item.Level,
                    \ }
        call add(entries, entry)
    endfor
    return entries
endfunction

" vim: ts=4 sw=4 et
