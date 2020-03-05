fu source#op(type, ...) abort "{{{1
    let cb_save  = &cb
    let sel_save = &selection
    let reg_save = ['"', getreg('"'), getregtype('"')]

    try
        set cb-=unnamed cb-=unnamedplus
        set selection=inclusive

        if a:type is# 'char'
            sil norm! `[v`]y
        elseif a:type is# 'line'
            sil norm! '[V']y
        elseif a:type is# 'block'
            sil exe "norm! `[\<c-v>`]y"
        elseif a:type is# 'vis'
            sil norm! gvy
        elseif a:type is# 'Ex'
            sil exe a:2..','..a:3..'y'
        else
            return ''
        endif
        let lines = split(@", "\n")

    catch
        return lg#catch_error()

    finally
        let &cb  = cb_save
        let &sel = sel_save
        call call('setreg', reg_save)
    endtry

    call filter(lines, {_,v -> v !~# '\~$\|[⇔→]\|^\s*[│─└┘┌┐]\|^[↣↢]\|^\s*\%(v\+\|\^\+\)\s*$'})
    if empty(lines) | return | endif
    call map(lines, {_,v -> substitute(v, '[✘✔┊].*', '', '')})
    call map(lines, {_,v -> substitute(v, '\C^\s*\%(fu\%[nction]\|com\%[mand]\)\zs\ze\s', '!', '')})
    let initial_indent = len(matchstr(lines[0], '^\s*'))
    " Why?{{{
    "
    " Here is the output of a sed command in the shell:
    "
    "     $ sed 's/\t/\
    "     /2' <<<'Column1	Column2	Column3	Column4'
    "     Column1	Column2~
    "     Column3	Column4~
    "
    " Here is the output of the same command when sourced with our plugin:
    "
    "     $ sed 's/\t/\
    "     /2' <<<'Column1	Column2	Column3	Column4'
    "     Column1 Column2~
    "         Column3     Column4~
    "
    " The indentation of the second line alters the output.
    " We must remove it to get the same result as in the shell.
    "}}}
    " Warning:{{{
    "
    " This can alter the result of a heredoc assignment.
    "
    " MWE:
    "
    "         let a =<< END
    "         xx
    "     END
    "     echo a
    "
    " If you run `:so%`, the output will be:
    "
    "     ['    xx']
    "       ^^^^
    "
    " If you press `+sip`, the output will be:
    "
    "     ['xx']
    "
    " In practice, I doubt it will be an issue because I think we'll always use `trim`:
    "
    "                   vvvv
    "         let a =<< trim END
    "         xx
    "     END
    "     echo a
    "}}}
    call map(lines, {_,v -> substitute(v, '^\s\{'..initial_indent..'}', '', '')})
    let tempfile = tempname()
    call writefile([''] + lines, tempfile, 'b')

    " we're sourcing a shell command
    let prompt = matchstr(lines[0], '^\s*\zs[$%]\ze\s')
    if prompt isnot# '' || s:is_in_embedded_shell_code_block()
        exe 'sp '..tempfile
        call source#fix_shell_cmd()
        sil update
        q
        if prompt isnot# ''
            sil let @o = system({'$': 'bash', '%': 'zsh'}[prompt]..' '..tempfile)
        else
            sil let @o = system('bash '..tempfile)
        endif
        echo @o
        return
    endif

    " we're sourcing a vimL command
    try
        " the function was invoked via the Ex command
        if a:0
            if exists(':ToggleEditingCommands') == 2
                ToggleEditingCommands 0
            endif

            let cmd = a:1..'verb source '..tempfile
            "         │
            "         └ use the verbosity level passed as an argument to `:SourceSelection`

        " the function was invoked via the mapping
        else
            let cmd = 'source '..tempfile
        endif

        " Flush any delayed screen updates before running `cmd`.
        " See `:h :echo-redraw`.
        redraw
        " save the output  in register `o` so we can  directly paste it wherever
        " we want; but remove the first newline before
        let @o = execute(cmd, '')[1:]
        " Don't run `:exe cmd`!{{{
        "
        " If you do, the code will be run twice (because you've just run `execute()`).
        " But if the code is not idempotent, the printed result may seem unexpected.
        " MWE:
        "
        "     let list = range(1, 4)
        "     call add(list, remove(list, 0))
        "     echo list
        "     [3, 4, 1, 2]~
        "
        " Here, the output should be:
        "
        "     [4, 1, 2, 3]~
        "}}}

    catch
        let @o = substitute(v:exception, '^Vim(.\{-}):', '', '')
        return lg#catch_error()
    finally
        if a:0 && exists(':ToggleEditingCommands') == 2
            ToggleEditingCommands 1
        endif
    endtry
endfu

fu source#fix_shell_cmd() abort "{{{1
    let pos = getcurpos()
    " remove a possible dollar/percent sign in front of the command
    let pat = '^\%(\s*\n\)*\s*\zs[$%]\s\+'
    let lnum = search(pat)
    if lnum
        let text = substitute(getline(lnum), '^\s*\zs[$%]\s\+', '', '')
        call setline(lnum, text)
    endif

    " remove possible indentation in front of `EOF`
    let pat = '\C^\%(\s*EOF\)\n\='
    let lnum = search(pat)
    let line = getline(lnum)
    let indent = matchstr(line, '^\s*')
    let range = '1/<<.*EOF/;/^\s*EOF/'
    let mods = 'keepj keepp '
    if !empty(indent)
        sil exe mods..range..'s/^'..indent..'//e'
        sil exe mods..''']+s/^'..indent..')/)/e'
    endif

    " Purpose:{{{
    "
    "     $ C-x C-e
    "     " press `o` to open a new line
    "     " insert `ls`
    "     " press `Esc` and `ZZ`
    "     # press Enter to run the command
    "     # press `M-c` to capture the pane contents via the capture-pane command from tmux:
    "     " notice how `ls(1)` is not visible in the quickfix window
    "}}}
    if getline(1) =~# '^\s*$'
        sil exe mods..'1;/\S/-d_'
    endif

    call setpos('.', pos)
endfu

fu s:is_in_embedded_shell_code_block() abort "{{{1
    let synstack = map(synstack(line('.'), col('.')), {_,v -> synIDattr(v, 'name')})
    return get(synstack, 0, '') =~# '^markdownHighlightz\=sh$'
endfu

fu source#fix_selection() abort "{{{1
    let tempfile = tempname()
    if !has('nvim')
        let selection = @*
    else
        " TODO: In Nvim, why the fuck isn't `@*` updated after we select some text in a Nvim buffer?{{{
        "
        " MWE1:
        "
        "     $ nvim
        "     " select the word `hello` in your web browser
        "     :echo @*
        "     hello~
        "     ✔
        "     :h
        "     " press `V` to select the first line
        "     :echo @*
        "     hello~
        "     ✘
        "
        " MWE2:
        "
        "     $ vim
        "     :h
        "     V
        "     Esc
        "     $ xsel -o
        "     *help.txt*      For Vim version 8.1.  Last change: 2019 Jul 21~
        "
        "     $ nvim
        "     :h
        "     V
        "     Esc
        "     $ xsel -o
        "     ''~
        "
        " ---
        "
        " I suspect it's a known limitation:
        "
        " >     ... since nvim  is not the direct owner of  the selection, we cannot
        " >     update the * register on demand as [g]vim does.
        "
        " Source: https://github.com/neovim/neovim/pull/3708
        "
        " See also: https://github.com/neovim/neovim/issues/4773
        "}}}
        let reg_save = [getreg('"'), getregtype('"')]
        sil norm! gvy
        let selection = @"
        call setreg('"', reg_save[0], reg_save[1])
    endif
    call writefile(split(selection, '\n'), tempfile)
    let s:star_save = [getreg('*'), getregtype('*')]
    let @* = ''
    call timer_start(0, {-> execute('so '..tempfile, '')})

    au CmdlineLeave * ++once call setreg('*', s:star_save[0], s:star_save[1])
        \ | unlet! s:star_save
endfu

