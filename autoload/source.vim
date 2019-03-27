fu! source#fix_selection() abort "{{{1
    let tempfile = tempname()
    call writefile(split(@*, '\n'), tempfile)
    let s:star_save = [getreg('*'), getregtype('*')]
    let @* = ''
    call timer_start(0, {-> execute('so '.tempfile)})

    augroup my_restore_selection
        au!
        au CmdlineLeave * sil! call setreg('*', s:star_save[0], s:star_save[1])
            \ | unlet! s:star_save
            \ | exe 'au! my_restore_selection' | aug! my_restore_selection
    augroup END
endfu

fu! source#fix_shell_cmd() abort "{{{1
    " remove a possible dollar sign in front of the command
    let pat = '^\%(\s*\n\)*\s*\zs\$'
    let lnum = search(pat)
    if lnum
        let text = substitute(getline(lnum), '^\s*\zs\$', '', '')
        call setline(lnum, text)
    endif

    " remove possible indentation in front of `EOF`
    let pat = '\C^\%(\s*EOF\)\n\='
    let lnum = search(pat)
    let line = getline(lnum)
    let indent = matchstr(line, '^\s*')
    let range = '1/<<.*EOF/;/^\s*EOF/'
    if !empty(indent)
        sil exe range.'s/'.indent.'//e'
    endif
endfu

fu! source#op(type, ...) abort "{{{1
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
            sil exe a:2.','.a:3.'y'
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

    if empty(lines)
        return
    endif

    call filter(lines, {i,v -> v !~# '\~$\|[⇔→│─└┘┌┐]\|^[↣↢]\|^\s*[v^ \t]$'})
    call map(lines, {i,v -> substitute(v, '[✘✔┊].*', '', '')})
    let initial_indent = strlen(matchstr(lines[0], '^\s*'))
    " Why?{{{
    "
    " Here's the output of a sed command in the shell:
    "
    "     $ sed 's/\t/\
    "     /2' <<<'Column1	Column2	Column3	Column4'
    "     Column1	Column2~
    "     Column3	Column4~
    "
    " Here's the output of the same command when sourced with our plugin:
    "
    "     $ sed 's/\t/\
    "     /2' <<<'Column1	Column2	Column3	Column4'
    "     Column1 Column2~
    "         Column3     Column4~
    "
    " The indentation of the second line alters the output.
    " We must remove it to get the same result as in the shell.
    "}}}
    call map(lines, {i,v -> substitute(v, '^\s\{'.initial_indent.'}', '', '')})
    let tempfile = tempname()
    call writefile([''] + lines, tempfile, 'b')

    " we're sourcing a shell command
    let prompt = matchstr(lines[0], '^\s*\zs\%(\$\|%\)\ze\s')
    if prompt isnot# ''
        exe 'sp '.tempfile
        call source#fix_shell_cmd()
        sil update
        close
        sil let @o = system({'$': 'bash', '%': 'zsh'}[prompt] . ' ' . tempfile)
        let @o = substitute(@o, '\n$', '', '')
        echo @o
        return
    endif

    " we're sourcing a vimL command
    try
        " the function was invoked via the Ex command
        if a:0
            if exists(':ToggleEditingCommands') ==# 2
                ToggleEditingCommands 0
            endif

            let cmd = a:1.'verb source '.tempfile
            "         │
            "         └ use the verbosity level passed as an argument to `:SourceSelection`

        " the function was invoked via the mapping
        else
            let cmd = 'source '.tempfile
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
        if a:0 && exists(':ToggleEditingCommands') ==# 2
            ToggleEditingCommands 1
        endif
    endtry
endfu

