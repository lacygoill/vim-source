vim9script noclear

import {
    Catch,
    Opfunc,
} from 'lg.vim'
const SID: string = execute('function Opfunc')->matchstr('\C\<def\s\+\zs<SNR>\d\+_')

var source_tempfile: string

# Interface {{{1
def source#op(): string #{{{2
    &operatorfunc = SID .. 'Opfunc'
    g:operatorfunc = {core: Source}
    return 'g@'
enddef

def source#fixSelection() #{{{2
    var tempfile: string = tempname()
    getreg('*', true, true)
        ->map((_, v: string) =>
                v->substitute('^\C\s*com\%[mand]\s', 'command! ', '')
                 ->substitute('^\C\s*fu\%[nction]\s', 'function! ', ''))
        ->writefile(tempfile)

    var star_save: dict<any> = getreginfo('*')
    setreg('*', {})
    timer_start(0, function(Sourcethis, [tempfile, star_save]))
enddef

def Sourcethis(
    tempfile: string,
    star_save: dict<any>,
    _
)
    try
        execute 'source ' .. tempfile
    catch
        echohl ErrorMsg
        echomsg v:exception
        echohl NONE
    finally
        setreg('*', star_save)
    endtry
enddef
#}}}1
# Core {{{1
def Source(type: string, verbosity = 0)
# Warning: If you run `:update`, don't forget `:lockmarks`.
# Otherwise, the change marks would be unexpectedly reset.

    var to_ignore: string = '˜$'
        .. '\|' .. '[⇔→]'
        .. '\|' .. '^\s*[│─└┘┌┐]'
        .. '\|' .. '^[↣↢]'
        .. '\|' .. '^\s*\%([-v]\+\|[-^]\+\)\s*$'
    var lines: list<string> = getreg('"')
        ->split('\n')
        ->filter((_, v: string): bool => v !~ to_ignore)

    if empty(lines)
        return
    endif

    if &filetype == 'vim'
        lines = ['vim9script'] + lines
    endif

    if source_tempfile == ''
        silent! delete(source_tempfile)
        source_tempfile = ''
    endif
    source_tempfile = tempname()

    var initial_indent: number = lines[0]
        ->matchstr('^\s*')
        ->strcharlen()
    lines
        ->map((_, v: string) =>
            v->substitute('[✘✔┊].*', '', '')
             ->substitute('^\C\s*\%(fu\%[nction]\|com\%[mand]\)\zs\ze\s', '!', '')
             # Why?{{{
             #
             # Here is the output of a sed command in the shell:
             #
             #     $ sed 's/\t/\
             #     /2' <<<'Column1	Column2	Column3	Column4'
             #     Column1	Column2˜
             #     Column3	Column4˜
             #
             # Here is the output of the same command when sourced with our plugin:
             #
             #     $ sed 's/\t/\
             #     /2' <<<'Column1	Column2	Column3	Column4'
             #     Column1 Column2˜
             #         Column3     Column4˜
             #
             # The indentation of the second line alters the output.
             # We must remove it to get the same result as in the shell.
             #}}}
             # Warning:{{{
             #
             # This can alter the result of a heredoc assignment.
             #
             # MWE:
             #
             #         let a =<< END
             #         xx
             #     END
             #     echo a
             #
             # If you run `:source %`, the output will be:
             #
             #     ['    xx']
             #       ^--^
             #
             # If you press `+sip`, the output will be:
             #
             #     ['xx']
             #
             # In practice,  I doubt it will  be an issue because  I think we'll
             # always use `trim`:
             #
             #                   v--v
             #         let a =<< trim END
             #         xx
             #     END
             #     echo a
             #}}}
             ->substitute('^\s\{' .. initial_indent .. '}', '', ''))

    writefile([''] + lines, source_tempfile, 'b')

    # we're sourcing a shell command
    var prompt: string = lines[0]->matchstr('^\s*\zs[$%]\ze\s')
    if prompt != '' || IsInEmbeddedShellCodeBlock()
        execute 'split ' .. source_tempfile
        source#fixShellCmd()
        quit
        var interpreter: string = 'bash'
        if prompt != ''
            interpreter = {
                '$': 'bash',
                '%': 'zsh'
            }[prompt]
        endif
        silent systemlist(interpreter .. ' ' .. source_tempfile)
            ->setreg('o', 'c')
        echo @o
        return
    endif

    # we're sourcing a vimscript command
    try
        var cmd: string
        if type == 'Ex'
            cmd = verbosity .. 'verbose source ' .. source_tempfile

        # the function was invoked via the mapping
        else
            cmd = 'source ' .. source_tempfile
        endif

        # Flush any delayed screen updates before running `cmd`.
        # See `:help :echo-redraw`.
        redraw
        # save the output  in register `o` so we can  directly paste it wherever
        # we want; but remove the first newline before
        setreg('o', [execute(cmd, '')[1 :]], 'c')
        # Don't run `:execute cmd`!{{{
        #
        # If you do, the code will be run twice (because you've just run `execute()`).
        # But if the code is not idempotent, the printed result may seem unexpected.
        # MWE:
        #
        #     var list: list<number> = range(1, 4)
        #     list->add(list->remove(0))
        #     echo list
        #     [3, 4, 1, 2]˜
        #
        # Here, the output should be:
        #
        #     [4, 1, 2, 3]˜
        #}}}

        # Add the current  line to the history  to be able to  insert its output
        # into the buffer with `C-r X`.
        if type == 'line' && line("'[") == line("']")
            getline('.')->histadd(':')
        endif
    catch
        setreg('o', [v:exception->substitute('^Vim(.\{-}):', '', '')], 'c')
        Catch()
        return
    endtry
enddef

def source#range( #{{{2
    lnum1: number,
    lnum2: number,
    verbosity: number
)
    var reginfo: dict<any> = getreginfo('"')
    var clipboard_save: string = &clipboard
    try
        &clipboard = ''
        execute ':' .. lnum1 .. ',' .. lnum2 .. 'yank'
        Source('Ex', verbosity)
    catch
        Catch()
        return
    finally
        &clipboard = clipboard_save
        setreg('"', reginfo)
    endtry
enddef

def IsInEmbeddedShellCodeBlock(): bool #{{{2
    return synstack('.', col('.'))
        ->mapnew((_, v: number): string => synIDattr(v, 'name'))
        ->get(0, '') =~ '^markdownHighlightz\=sh$'
enddef

def source#fixShellCmd() #{{{2
    var pos: list<number> = getcurpos()

    # remove a possible dollar/percent sign in front of the command
    var pat: string = '^\%(\s*\n\)*\s*\zs[$%]\s\+'
    var lnum: number = search(pat)
    if lnum > 0
        getline(lnum)
            ->substitute('^\s*\zs[$%]\s\+', '', '')
            ->setline(lnum)
    endif

    # remove possible indentation in front of `EOF`
    pat = '\C^\%(\s*EOF\)\n\='
    lnum = search(pat)
    var line: string = getline(lnum)
    var indent: string = line->matchstr('^\s*')
    var range: string = ':1/<<.*EOF/;/^\s*EOF/'
    var mods: string = 'silent keepjumps keeppatterns '
    if !empty(indent)
        execute mods .. range .. 'substitute/^' .. indent .. '//e'
        execute mods .. ':'']+1 substitute/^' .. indent .. ')/)/e'
    endif

    # Remove empty lines at the top of the buffer.{{{
    #
    #     $ C-x C-e
    #     # press `o` to open a new line
    #     # insert `ls`
    #     # press `Esc` and `ZZ`
    #     # press Enter to run the command
    #     # press `M-c` to capture the pane contents via the capture-pane command from tmux
    #     # notice how `ls(1)` is not visible in the quickfix window
    #}}}
    # Why the autocmd?{{{
    #
    # To avoid some weird issue when starting Vim via `C-x C-e`.
    #
    #     :let @+ = "\n\x1b[201~\\n\n"
    #     # start a terminal other than xterm
    #     # press C-x C-e
    #     # enter insert mode and press C-S-v
    #     # keep pressing undo
    #
    # Vim keeps undoing new changes indefinitely.
    #
    #     :echo undotree()
    #     E724: variable nested too deep for displaying˜
    #
    # MWE:
    #
    #       inoremap <C-M> <C-G>u<CR>
    #       let &t_PE = "\<Esc>[201~"
    #       autocmd TextChanged * 1;/\S/-d
    #       let @+ = "\n\x1b[201~\\n\n"
    #       startinsert
    #
    #       # press:  C-S-v Esc u u u ...
    #
    # To  avoid  this,   we  delay  the  deletion  until  we   leave  Vim  (yes,
    # `BufWinLeave` is fired when we leave Vim; but not `WinLeave`).
    #}}}
    if !exists('#FixShellcmd') # no need to re-install the autocmd on every `TextChanged` or `InsertLeave`
        augroup FixShellcmd | autocmd!
            autocmd BufWinLeave <buffer> ++once FixShellcmd()
        augroup END
    endif

    setpos('.', pos)
enddef

def FixShellcmd()
    abuf = expand('<abuf>')->str2nr()
    # find where the buffer is now
    winids = win_findbuf(abuf)
    # make sure we're in its window
    if empty(winids)
        execute 'buffer ' .. abuf
    else
        win_gotoid(winids[0])
    endif
    # remove empty lines at the top
    if getline(1) !~ '\S'
        silent! keepjumps keeppatterns :1;/\S/-1 delete _
        update
    endif
enddef

var abuf: number
var winids: list<number>

