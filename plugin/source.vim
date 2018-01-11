if exists('g:loaded_source')
    finish
endif
let g:loaded_source = 1

" Warning:{{{
" When you  press `+sip` to source  a block of code,  you're in operator-pending
" mode. This means that if your code includes `mode(1)`, it will be evaluated in
" 'no', not 'n'.
"
" Watch:
"
"     fu! Func()
"         echo mode(1)
"     endfu
"     call Func()
"
" Write this in a file, and source it with `+S`:    'n'
" Now, source it again with `+sip`:                 'no'
"}}}

" Command {{{1

"                         ┌─ Source Selection
"                         │                               ┌─ verbosity level
"                         │                               │
com! -bar -nargs=? -range SS call source#op('Ex', !empty(<q-args>) ? <q-args> : 0, <line1>, <line2>)

" Mappings {{{1

nno  <silent><unique>  +S  :<c-u>sil! update<bar>source %<cr>
nno  <silent><unique>  +s  :<c-u>sil! update<bar>set opfunc=source#op<cr>g@
" Why do we add the current line to the history?
" To be able to insert its output into the buffer with `C-r X`.
nno  <silent><unique>  +ss  :<c-u>sil! update<bar>set opfunc=source#op
                            \<bar>exe 'norm! '.v:count1.'g@_'
                            \<bar>if line("'[") == line("']") <bar> call histadd(':', getline('.')) <bar> endif<cr>
xno  <silent><unique>  +s   :<c-u>sil! update<bar>call source#op('vis')<cr>

" Typo:
" Sometimes I don't  release AlgGr fast enough, so instead  of pressing `+s`, I
" press `+[`.
nmap  +[  +s
