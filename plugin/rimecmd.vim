function! Oneshot(append) abort
  let text_win = nvim_get_current_win()
  let current_cursor = nvim_win_get_cursor(text_win)
  let rimecmd_buf = nvim_create_buf(v:false, v:true)
  let rimecmd_window = nvim_open_win(
    \ rimecmd_buf, v:true, {
      \ 'relative': 'cursor',
      \ 'row': 1,
      \ 'col': 0,
      \ 'height': 10,
      \ 'width': 40,
      \ 'focusable': v:true,
      \ 'border': 'single',
      \ 'title': 'rimecmd window',
      \ 'noautocmd': v:true,
    \ }
  \ )

  function! OnStdout(job_id, data, event) abort closure
    let commit_string = a:data[0]
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if commit_string ==# ''
      return
    endif
    let cursor_pos = nvim_win_get_cursor(text_win)
    call nvim_buf_set_text(
      \ nvim_win_get_buf(text_win),
      \ cursor_pos[0] - 1,
      \ cursor_pos[1],
      \ cursor_pos[0] - 1,
      \ cursor_pos[1],
      \ [commit_string]
    \ )
    call nvim_win_set_cursor(
      \ text_win, [
        \ cursor_pos[0],
        \ cursor_pos[1] + strlen(commit_string)
      \ ],
    \ )
  endfunction
  function! OnExit(job_id, data, event) abort closure
    call nvim_win_close(rimecmd_window, v:true)
    call jobstart(
      \ ['rm', '-f', '/tmp/nvim_rimecmd_oneshot'],
      \ { 'detach': v:true },
    \ )
  endfunction
  " neovim has a bug. It treats data written to tty but not stdout
  " as data written to stdout. In other words, it treats all the output
  " used to draw the Rime menu as if they are written to stdout.
  " Therefore, we have to have this workaround to collect the real stdout
  " of rimecmd.
  let fifo_filename = tempname()
  let stdout_read_job_id = jobstart(
    \ printf("mkfifo %s && cat %s", fifo_filename, fifo_filename),
    \ {
      \ "on_stdout": function('OnStdout') 
    \ },
  \ )
  let rimecmd_job_id = termopen(
    \ printf("rimecmd > %s", fifo_filename),
    \ {
      \ 'on_exit': function('OnExit')
    \ }
  \ )
  if rimecmd_job_id == -1
    call nvim_win_close(rimecmd_window)
    echoerr "Cannot execute rimecmd. Is it available through your PATH?" 
  endif
  startinsert
endfunction
command! Rimecmd call Oneshot(v:false)
command! RimecmdAppend call Oneshot(v:true)
