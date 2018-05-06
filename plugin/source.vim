if exists('g:loaded_source')
    finish
endif
let g:loaded_source = 1

" Autocmd {{{1

" If  you try  to source  some code  visually  selected in  a buffer  or in  the
" web  browser, by  executing  `@*` on  the  command line,  and  if it  contains
" continuation lines, `<sid>` or `s:`, it will fail.
"
" To fix this, we write the selection in a file and source the latter.
augroup fix_source_selection
    au!
    au CmdlineLeave : if getcmdline() is# '@*'
    \ |                   call source#fix_selection()
    \ |               endif
augroup END

" Command {{{1

"                                                                      ┌─ verbosity level
"                                                                      │
com! -bar -nargs=? -range SourceSelection call source#op('Ex', !empty(<q-args>) ? <q-args> : 0, <line1>, <line2>)

" Mappings {{{1

" Warning:{{{
" When you  press `+sip` to source  a block of code,  you're in operator-pending
" mode. This means that if your code includes `mode(1)`, it will be evaluated as
" 'no', not 'n'.
"
" MWE:
"
"     fu! Func()
"         echo mode(1)
"     endfu
"     call Func()
"
" Write this in a file, and source it with `+S`:    'n'
" Now, source it again with `+sip`:                 'no'
"}}}

nno  <silent><unique>  +S  :<c-u>sil! update<bar>source %<cr>
nno  <silent><unique>  +s  :<c-u>sil! update<bar>set opfunc=source#op<cr>g@
" Why do we add the current line to the history?
" To be able to insert its output into the buffer with `C-r X`.
nno  <silent><unique>  +ss  :<c-u>sil! update<bar>set opfunc=source#op
                           \ <bar>exe 'norm! '.v:count1.'g@_'
                           \ <bar>if line("'[") ==# line("']") <bar> call histadd(':', getline('.')) <bar> endif<cr>
xno  <silent><unique>  +s   :<c-u>sil! update<bar>call source#op('vis')<cr>

" Typo:
" Sometimes I don't  release AlgGr fast enough, so instead  of pressing `+s`, I
" press `+[`.
nmap  +[  +s
