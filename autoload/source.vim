vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

import {Catch, Opfunc} from 'lg.vim'
const SID: string = execute('fu Opfunc')->matchstr('\C\<def\s\+\zs<SNR>\d\+_')

# Interface {{{1
def source#op(): string #{{{2
    &opfunc = SID .. 'Opfunc'
    g:opfunc = {core: 'source#opCore'}
    return 'g@'
enddef

def source#opCore(type: string, verbosity = 0)
    # Warning: If you run `:update`, don't forget `:lockm`.
    # Otherwise, the change marks would be unexpectedly reset.
    var lines: list<string> = split(@", "\n")

    filter(lines, (_, v) => v !~ '\~$\|[⇔→]\|^\s*[│─└┘┌┐]\|^[↣↢]\|^\s*\%([-v]\+\|[-^]\+\)\s*$')
    if empty(lines)
        return
    endif
    map(lines, (_, v) => substitute(v, '[✘✔┊].*', '', ''))
    map(lines, (_, v) => substitute(v, '\C^\s*\%(fu\%[nction]\|com\%[mand]\)\zs\ze\s', '!', ''))
    var initial_indent: number = matchstr(lines[0], '^\s*')->strlen()
    # Why?{{{
    #
    # Here is the output of a sed command in the shell:
    #
    #     $ sed 's/\t/\
    #     /2' <<<'Column1	Column2	Column3	Column4'
    #     Column1	Column2~
    #     Column3	Column4~
    #
    # Here is the output of the same command when sourced with our plugin:
    #
    #     $ sed 's/\t/\
    #     /2' <<<'Column1	Column2	Column3	Column4'
    #     Column1 Column2~
    #         Column3     Column4~
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
    # If you run `:so%`, the output will be:
    #
    #     ['    xx']
    #       ^--^
    #
    # If you press `+sip`, the output will be:
    #
    #     ['xx']
    #
    # In practice, I doubt it will be an issue because I think we'll always use `trim`:
    #
    #                   v--v
    #         let a =<< trim END
    #         xx
    #     END
    #     echo a
    #}}}
    map(lines, (_, v) => substitute(v, '^\s\{' .. initial_indent .. '}', '', ''))
    if source_tempfile == ''
        sil! delete(source_tempfile)
        source_tempfile = ''
    endif
    source_tempfile = tempname()
    writefile([''] + lines, source_tempfile, 'b')

    # we're sourcing a shell command
    var prompt: string = matchstr(lines[0], '^\s*\zs[$%]\ze\s')
    if prompt != '' || IsInEmbeddedShellCodeBlock()
        exe 'sp ' .. source_tempfile
        source#fixShellCmd()
        q
        if prompt != ''
            sil setreg('o', systemlist({
                '$': 'bash',
                '%': 'zsh'
                }[prompt]
                .. ' ' .. source_tempfile), 'c')
        else
            sil setreg('o', systemlist('bash ' .. source_tempfile), 'c')
        endif
        echo @o
        return
    endif

    # we're sourcing a vimL command
    try
        var cmd: string
        if type == 'Ex'
            if exists(':ToggleEditingCommands') == 2
                ToggleEditingCommands 0
            endif

            cmd = verbosity .. 'verb source ' .. source_tempfile

        # the function was invoked via the mapping
        else
            cmd = 'source ' .. source_tempfile
        endif

        # Flush any delayed screen updates before running `cmd`.
        # See `:h :echo-redraw`.
        redraw
        # save the output  in register `o` so we can  directly paste it wherever
        # we want; but remove the first newline before
        setreg('o', [execute(cmd, '')[1 :]], 'c')
        # Don't run `:exe cmd`!{{{
        #
        # If you do, the code will be run twice (because you've just run `execute()`).
        # But if the code is not idempotent, the printed result may seem unexpected.
        # MWE:
        #
        #     var list: list<number> = range(1, 4)
        #     add(list, remove(list, 0))
        #     echo list
        #     [3, 4, 1, 2]~
        #
        # Here, the output should be:
        #
        #     [4, 1, 2, 3]~
        #}}}

        # Add the current  line to the history  to be able to  insert its output
        # into the buffer with `C-r X`.
        if type == 'line' && line("'[") == line("']")
            getline('.')->histadd(':')
        endif
    catch
        setreg('o', [substitute(v:exception, '^Vim(.\{-}):', '', '')], 'c')
        Catch()
        return
    finally
        if type == 'Ex' && exists(':ToggleEditingCommands') == 2
            ToggleEditingCommands 1
        endif
    endtry
enddef

var source_tempfile: string

def source#fixSelection() #{{{2
    var tempfile: string = tempname()
    var selection: list<string> = getreg('*', true, true)
    map(selection, (_, v) => substitute(v, '^\C\s*com\%[mand]\s', 'command! ', ''))
    map(selection, (_, v) => substitute(v, '^\C\s*fu\%[nction]\s', 'function! ', ''))
    writefile(selection, tempfile)
    var star_save: dict<any> = getreginfo('*')
    setreg('*', {})
    timer_start(0, function(Sourcethis, [tempfile, star_save]))
enddef

def Sourcethis(tempfile: string, star_save: dict<any>, _: any)
    try
        exe 'so ' .. tempfile
    catch
        echohl ErrorMsg
        echom v:exception
        echohl NONE
    finally
        setreg('*', star_save)
    endtry
enddef
#}}}1
# Core {{{1
def source#range(lnum1: number, lnum2: number, verbosity: number) #{{{2
    var reginfo: dict<any> = getreginfo('"')
    var cb_save: string = &cb
    try
        set cb=
        exe ':' .. lnum1 .. ',' .. lnum2 .. 'y'
        source#opCore('Ex', verbosity)
    catch
        Catch()
        return
    finally
        &cb = cb_save
        setreg('"', reginfo)
    endtry
enddef

def IsInEmbeddedShellCodeBlock(): bool #{{{2
    var synstack: list<string> = synstack('.', col('.'))
        ->mapnew((_, v) => synIDattr(v, 'name'))
    return get(synstack, 0, '') =~ '^markdownHighlightz\=sh$'
enddef

def source#fixShellCmd() #{{{2
    var pos: list<number> = getcurpos()

    # remove a possible dollar/percent sign in front of the command
    var pat: string = '^\%(\s*\n\)*\s*\zs[$%]\s\+'
    var lnum: number = search(pat)
    if lnum > 0
        var text: string = getline(lnum)->substitute('^\s*\zs[$%]\s\+', '', '')
        setline(lnum, text)
    endif

    # remove possible indentation in front of `EOF`
    pat = '\C^\%(\s*EOF\)\n\='
    lnum = search(pat)
    var line: string = getline(lnum)
    var indent: string = matchstr(line, '^\s*')
    var range: string = ':1/<<.*EOF/;/^\s*EOF/'
    var mods: string = 'keepj keepp '
    if !empty(indent)
        sil exe mods .. range .. 's/^' .. indent .. '//e'
        sil exe mods .. ':'']+s/^' .. indent .. ')/)/e'
    endif

    # Remove empty lines at the top of the buffer.{{{
    #
    #     $ C-x C-e
    #     " press `o` to open a new line
    #     " insert `ls`
    #     " press `Esc` and `ZZ`
    #     # press Enter to run the command
    #     # press `M-c` to capture the pane contents via the capture-pane command from tmux
    #     " notice how `ls(1)` is not visible in the quickfix window
    #}}}
    # Why the autocmd?{{{
    #
    # To avoid some weird issue when starting Vim via `C-x C-e`.
    #
    #     :let @+ = "\n\x1b[201~\\n\n"
    #     # start a terminal other than xterm
    #     # press C-x C-e
    #     " enter insert mode and press C-S-v
    #     " keep pressing undo
    #
    # Vim keeps undoing new changes indefinitely.
    #
    #     :echo undotree()
    #     E724: variable nested too deep for displaying~
    #
    # MWE:
    #
    #     $ vim -Nu NONE \
    #       +'ino <c-m> <c-g>u<cr>' \
    #       +'let &t_PE = "\e[201~"' \
    #       +'au TextChanged * 1;/\S/-d' \
    #       +'let @+ = "\n\x1b[201~\\n\n"' \
    #       +startinsert
    #
    #     " press:  C-S-v Esc u u u ...
    #
    # To  avoid  this,   we  delay  the  deletion  until  we   leave  Vim  (yes,
    # `BufWinLeave` is fired when we leave Vim; but not `WinLeave`).
    #}}}
    if !exists('#FixShellcmd') # no need to re-install the autocmd on every `TextChanged` or `InsertLeave`
        augroup FixShellcmd | au!
            au BufWinLeave <buffer> ++once FixShellcmd()
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
        exe 'b ' .. abuf
    else
        win_gotoid(winids[0])
    endif
    # remove empty lines at the top
    if getline(1) =~ '^\s*$'
        sil! keepj keepp :1;/\S/-d _
        update
    endif
enddef

var abuf: number
var winids: list<number>

