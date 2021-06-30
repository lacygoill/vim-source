vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Autocmd {{{1

# If  you try  to source  some code  visually  selected in  a buffer  or in  the
# web  browser, by  executing  `@*` on  the  command-line,  and  if it  contains
# continuation lines, `<SID>` or `s:`, it will fail.
#
# To fix this, we write the selection in a file and source the latter.
augroup FixSourceSelection | autocmd!
    autocmd CmdlineLeave : if getcmdline() == '@*'
        |     source#fixSelection()
        | endif
augroup END

# Command {{{1

command -bar -nargs=? -range
    \ SourceRange source#range(<line1>, <line2>, !empty(<q-args>) ? str2nr(<q-args>) : 0)

# Mappings {{{1

# Warning: `mode(true)` is `no` when sourcing code with the operator.{{{
#
# That's because, at that moment, you're really in operator-pending mode.
#
# MWE:
#
#     def Func()
#         echo mode(true)
#     enddef
#     Func()
#
# Write this in a file, and source it with `+S`:
#
#     n˜
#
# Now, source it again with `+sip`:
#
#     no˜
#}}}

# FIXME: `+s` is unable to print 2 or more messages; only the last one is kept:{{{
#
#     " uncomment the next line, and press `+ss`
#     echo 'foo' | echo 'bar'
#
# It seems impossible to echo several  messages from an operator function (or an
# autocmd, or a timer...).  For more info, read our notes about mappings, and:
# https://github.com/lervag/vimtex/pull/1247
#}}}
nnoremap <unique> +S <Cmd>silent! update <Bar> source %<CR>
nnoremap <expr><unique> +s source#op()
xnoremap <expr><unique> +s source#op()
nnoremap <expr><unique> +ss source#op() .. '_'

# Typo: Sometimes I don't release AlgGr fast enough, so instead of pressing `+s`, I press `+[`.
nmap +[ +s

