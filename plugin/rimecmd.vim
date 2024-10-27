function! Oneshot() abort
  let current_buf = nvim_win_get_buf(0)
  let current_cursor = nvim_win_get_cursor(0)
  let rimecmd_buf = nvim_create_buf(v:false, v:true)
  let rimecmd_window = nvim_open_win(
    \ rimecmd_buf, v:true, {
      \ 'relative': 'cursor',
      \ 'row': 1,
      \ 'col': 0,
      \ 'height': 10,
      \ 'width': 20,
      \ 'focusable': v:true,
      \ 'border': 'single',
      \ 'title': 'rimecmd window',
      \ 'noautocmd': v:true,
    \ }
  \ )

  function! InsertCommitString(commit_string, buffer, pos) abort
    call nvim_buf_set_text(
      \ a:buffer,
      \ a:pos[0],
      \ a:pos[1],
      \ a:pos[0],
      \ a:pos[1],
      \ [a:commit_string]
    \ )
  endfunction
  function! CleanUp(rimecmd_window_to_close) abort
    call nvim_win_close(a:rimecmd_window_to_close, v:true)
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
      \ "on_stdout": { job_id, data, event -> InsertCommitString(
        \ data[0], current_buf, [current_cursor[0] - 1, current_cursor[1]]
      \ )}
    \ },
  \ )
  let rimecmd_job_id = termopen(
    \ printf("rimecmd > %s", fifo_filename),
    \ {
      \ 'on_exit': {job_id, exitcode, event -> CleanUp(rimecmd_window)},
    \ }
  \ )
  if rimecmd_job_id == -1
    call nvim_win_close(rimecmd_window)
    echoerr "Cannot execute rimecmd. Is it available through your PATH?" 
  endif
  startinsert
endfunction
command! Rimecmd call Oneshot()
