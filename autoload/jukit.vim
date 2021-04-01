fun! s:SelectSection()
    " Selects the text between 2 cell markers
    
    set nowrapscan

    let line_before_search = line(".")
    silent! exec '/|%%--%%|'
    " check if line has changed, otherwise no section AFTER the current one
    " was found
    if line(".")!=line_before_search
        normal! k$v
    else
        normal! G$v
    endif
    let line_before_search = line(".")
    silent! exec '?|%%--%%|'
    " check if line has changed, otherwise not section BEFORE the current one
    " was found
    if line(".")!=line_before_search
        normal! j0
    else
        normal! gg
    endif

    let &wrapscan = s:wrapscan
endfun


function! s:GetVisualSelection()
    " Credit for this function: 
    " https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction


fun! s:ParseRegister()
    " Gets content of register and send to kitty window
    
python3 << EOF
import vim 
import json

reg = vim.eval('s:jukit_register')
reg_conent = vim.eval(f'@{reg}')
if reg_conent[-1]!="\n":
    reg_conent += "\n"
escaped = reg_conent.translate(str.maketrans({
    "\n": "\\\n",
    "\\": "\\\\",
    '"': '\\"',
    "'": "\\'",
    "#": "\\#",
    "!": "\!",
    "%": "\%",
    "|": "\|",
    }))
 
vim.command("let escaped_text = shellescape({})".format(json.dumps(escaped)))
EOF
    let command = '!kitty @ send-text --match title:' . b:output_title . ' ' . escaped_text
    return command
endfun


fun! jukit#PythonSplit(...)
    " Opens new kitty window split and opens python

    " check if ipython is used
    let b:ipython = split(s:python_cmd, '/')[-1] == 'ipython'
    " define title of new kitty window by which we match when sending
    let b:output_title=strftime("%Y%m%d%H%M%S")
    " create new window
    silent exec "!kitty @ launch --keep-focus --title " . b:output_title
        \ . " --cwd=current"

    " if an argument was given, execute it in new kitty terminal window before
    " starting python shell
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . a:1 . "\r"
    endif

    if b:inline_plotting == 1
        " if inline plotting is enabled, use helper script to check if the
        " required backend is in python path and otherwise create it
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " python3 " . s:plugin_path . "/helpers/check_matplotlib_backend.py "
            \ . s:plugin_path . "\r"
        " open python and import the matplotlib with the backend required
        " backend first
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . s:python_cmd . " -i -c \"\\\"import matplotlib;
            \ matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\r"
    else
        " if no inline plotting is desired, simply open python
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . s:python_cmd . "\r"
    endif
endfun


fun! jukit#ReplSplit()
    " Opens a new kitty terminal window

    let b:ipython = 0
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


fun! jukit#SendLine()
    " Sends a single line to the other kitty terminal window

    if b:ipython==1
        " if ipython is used, copy code to system clipboard and '%paste'
        " to register
        normal! 0v$"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank line to register
        exec 'normal! 0v$"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    normal! j
    redraw!
endfun


fun! jukit#SendSelection()
    " Sends visually selected text to the other kitty terminal window
    
    if b:ipython==1
        " if ipython is used, copy visual selection to system clipboard and 
        " '%paste' to register
        let @+ = s:GetVisualSelection() 
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank content of visual selection to register
        exec 'let @' . s:jukit_register . ' = s:GetVisualSelection()'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!
endfun


fun! jukit#SendSection()
    " Sends the section of current cursor position to window

    " first select the whole current section
    call s:SelectSection()
    if b:ipython==1
        " if ipython is used, copy whole section to system clipboard and 
        " '%paste' to register
        normal! "+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank content of section to register
        exec 'normal! "' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!

    set nowrapscan
    " move to next section
    silent! exec '/|%%--%%|'
    let &wrapscan = s:wrapscan
    nohl
    normal! j
endfun


fun! jukit#SendUntilCurrentSection()
    " Sends all code until (and including) the current section to window

    " go to end of current section
    silent! exec '/|%%--%%|'
    if b:ipython==1
        " if ipython is used, copy from end of current section until 
        " file beginning to system clipboard and yank '%paste' to register
        normal! k$vggj"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise simply yank everything from beginning to current
        " section to register
        exec 'normal! k$vggj"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!
endfun


fun! jukit#SendAll()
    " Sends all code in file to window
    
    if b:ipython==1
        " if ipython is used, copy all code in file  to system clipboard 
        " and yank '%paste' to register
        normal! ggvG$"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise copy yank whole file content to register
        exec 'normal! ggvG$"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
endfun


fun! jukit#NewMarker()
    " Creates a new cell marker below

    if s:use_tcomment == 1
        " use tcomment plugin to automaticall detect comment marker of 
        " current filetype and comment line if specified
        exec 'normal! o |%%--%%|'
        call tcomment#operator#Line('g@$')
    else
        " otherwise simply prepend line with user b:comment_marker variable
        exec "normal! o" . b:comment_mark . ' |%%--%%|'
    endif
    normal! j
endfun


fun! jukit#NotebookConvert(from_notebook)
    " Converts from .ipynb to .py if a:from_notebook==1 and the otherway if
    " a:from_notebook==0

    if a:from_notebook == 1
        silent exec "!python3 " . s:plugin_path . "/helpers/ipynb_py_convert % %:r.py"
        exec "e %:r.py"
    elseif a:from_notebook == 0
        silent exec "!python3 " . s:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    endif
    redraw!
endfun


fun! jukit#SaveNBToFile(run, open, to)
    " Converts the existing .ipynb to the given filetype (a:to) - e.g. html or
    " pdf - and open with specified file viewer

    silent exec "!python3 " . s:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    if a:run == 1
        let command = "!jupyter nbconvert --to " . a:to
            \ . " --allow-errors --execute --log-level='ERROR' %:r.ipynb "
    else
        let command = "!jupyter nbconvert --to " . a:to . " --log-level='ERROR' %:r.ipynb "
    endif
    if a:open == 1
        exec 'let command = command . "&& " . s:' . a:to . '_viewer . " %:r.' . a:to . ' &"'
    else
        let command = command . "&"
    endif
    silent! exec command
    redraw!
endfun


fun! jukit#GetPluginPath(plugin_script_path)
    " Gets the absolute path to the plugin (i.e. to the folder vim-jukit/) 
    
    let plugin_path = a:plugin_script_path
    let plugin_path = split(plugin_path, "/")[:-3]
    return "/" . join(plugin_path, "/")
endfun


fun! s:InitBufVar()
    " Initialize buffer variables

    let b:inline_plotting = s:inline_plotting_default
    if s:use_tcomment != 1
        let b:comment_mark = s:comment_marker_default
    endif
endfun


""""""""""""""""""
" helper variables
let s:wrapscan = &wrapscan 
let s:plugin_path = jukit#GetPluginPath(expand("<sfile>"))


"""""""""""""""""""""""""
" User defined variables:
let s:use_tcomment = get(g:, 'use_tcomment', 0)
let s:inline_plotting_default = get(g:, 'inline_plotting_default', 1)
let s:comment_marker_default = get(g:, 'comment_marker_default', '#')
let s:pdf_viewer = get(g:, 'pdf_viewer', 'zathura')
let s:html_viewer = get(g:, 'html_viewer', 'firefox')
let s:python_cmd = get(g:, 'python_cmd', 'ipython')
let s:highlight_markers = get(g:, 'highlight_markers', 1)
let s:jukit_register = get(g:, 'jukit_register', 'x')


"""""""""""""""""""""""""""""
" initialize buffer variables
call s:InitBufVar()
autocmd BufEnter * call s:InitBufVar()
