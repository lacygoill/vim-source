fu! source#fix_selection() abort "{{{1
    let tempfile = tempname()
    call writefile(split(@*, '\n'), tempfile)

    " We've already “fixed” the selection, by writing it in a file, so why removing the continuation lines?{{{
    "
    " Continuation lines cause several errors, and a hit-enter prompt.
    " Even though our file is correctly sourced, the prompt is distracting.
    "}}}
    let @* = substitute(@*, '\n\s*\\', '', 'g')
    " You could also perform other substitutions, if needed in the future:{{{
    "
    " remove <sid>
    "     let @* = substitute(@*, '\%(<sid>\)\(\a\)', '\u\1', 'g')
    " remove script-local scope for functions
    "     let @* = substitute(@*, 'fu\%[nction]!\=\s\+\zss:\(\a\)', '\u\1', 'g')
    "}}}

    " Why a timer?{{{
    "
    " To prevent `E81`.
    "
    " For some reason,  if the selection contains the string  `<sid>`, it is not
    " translated in the mapping table.
    " Maybe because  when `CmdlineLeave` is  fired, we're in a  special context,
    " which prevents us from being in the context of a script.
    " Anyway, delaying the sourcing fixes the issue.
    "}}}
    " Why `:echo`?{{{
    "
    " The autocmd does NOT alter or prevent the execution of `@*`.
    " It will still be broken and executed.
    " From `:h CmdlineLeave`:
    "
    "     When the commands result in an error the
    "     command line is still executed.
    "
    " We can only start a new, fixed, command afterwards.
    "
    " So, there'll be an error message.
    " We don't want to see it; hence the `:echo`.
    "}}}
    " Why `norm! \e`?{{{
    "
    " Visually select this:
    "
    "     let qfl = getqflist({ 'lines': systemlist('find /etc/ -name "*.conf" -type f'),
    "     \                     'efm':   '%f'})
    "     call setqflist(get(qfl, 'items', []))
    "     cw
    "
    " Execute `:@*`.
    " The qf window is automatically opened.
    " Press `j`: the cursor moves on a line far below the original one.
    " I don't know why. But pressing Esc fixes the issue.
    "
    " Update:
    " It's due to some other autocmd.
    " Because if you prefix `:so` with `:noa`, the issue disappears.
    "}}}
    call timer_start(0, {-> execute('so '.tempfile.' | echo "" | norm! '."\e", '')})
endfu

fu! source#op(type, ...) abort "{{{1
    let cb_save  = &cb
    let sel_save = &selection
    let reg_save = [ '"', getreg('"'), getregtype('"') ]

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
        let raw_lines = split(@", "\n")

    catch
        return lg#catch_error()

    finally
        let &cb  = cb_save
        let &sel = sel_save
        call call('setreg', reg_save)
    endtry

    " We don't source the code by simply dumping it on the command-line:
    "
    "     :so @"
    "
    " It wouldn't work when the code contains continuation lines, or tabs
    " (trigger completion).
    "
    " So, instead, we dump it in a temporary file and source the latter.
    let lines     = filter(raw_lines, { i,v -> v !~# '[⇔→│└┌]\|^[↣↢]' })
    let lines     = map(raw_lines, { i,v -> substitute(v, '[✘✔┊].*', '', '') })
    let tempfile  = tempname()
    call writefile(lines, tempfile, 'b')

    try
        " the function was invoked via the Ex command
        if a:0
            if exists(':ToggleEditingCommands') ==# 2
                ToggleEditingCommands 0
            endif

            exe a:1.'verb source '.tempfile
            "   │
            "   └─ use the verbosity level passed as an argument to `:SourceSelection`

        " the function was invoked via the mapping
        else
            exe 'source '.tempfile
        endif

    catch
        return lg#catch_error()
    finally
        if a:0 && exists(':ToggleEditingCommands') ==# 2
            ToggleEditingCommands 1
        endif
    endtry
endfu

