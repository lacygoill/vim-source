if exists('g:loaded_source')
    finish
endif
let g:loaded_source = 1

" Autocmd {{{1

" If  you try  to source  some code  visually  selected in  a buffer  or in  the
" web  browser, by  executing  `@*` on  the  command-line,  and  if it  contains
" continuation lines, `<sid>` or `s:`, it will fail.
"
" To fix this, we write the selection in a file and source the latter.
augroup fix_source_selection | au!
    au CmdlineLeave : if getcmdline() is# '@*'
    \ |                   call source#fix_selection()
    \ |               endif
augroup END

" Command {{{1

com -bar -nargs=? -range SourceSelection call source#op(<line1>, <line2>,
    \ !empty(<q-args>) ? <q-args> : 0)
    "  │
    "  └ verbosity level

" Mappings {{{1

" Warning:{{{
" When you  press `+sip` to source  a block of code,  you're in operator-pending
" mode. This means that if your code includes `mode(1)`, it will be evaluated as
" 'no', not 'n'.
"
" MWE:
"
"     fu Func()
"         echo mode(1)
"     endfu
"     call Func()
"
" Write this in a file, and source it with `+S`:    'n'
" Now, source it again with `+sip`:                 'no'
"}}}

" FIXME: `+s` is unable to print 2 or more messages; only the last one is kept:{{{
"
"     " uncomment the next line, and press `+ss`
"     echo 'foo' | echo 'bar'
"
" It seems impossible to echo several messages from an opfunc (or an autocmd, or a timer...).
" For more info, read our notes about mappings, and: https://github.com/lervag/vimtex/pull/1247
"}}}
nno <silent><unique> +S :<c-u>sil! update<bar>source %<cr>
nno <expr><unique> +s source#op()
xno <expr><unique> +s source#op()
nno <expr><unique> +ss source#op()..'_'

" Typo:
" Sometimes I don't release AlgGr fast enough, so instead of pressing `+s`, I press `+[`.
nmap +[ +s
