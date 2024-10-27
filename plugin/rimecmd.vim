let s:extmark_ns = nvim_create_namespace('rimecmd')

function! NextCol(buf, cursor) abort
  let line_text = nvim_buf_get_lines(
    \ a:buf,
    \ a:cursor[0] - 1,
    \ a:cursor[0],
    \ v:true,
  \ )[0]
  return byteidx(
    \ line_text,
    \ charidx(line_text, min([a:cursor[1], strlen(line_text) - 1])) + 1,
  \ )
endfunction

function! Rimecmd(oneshot, append) abort
  let text_win = nvim_get_current_win()
  let rimecmd_buf = nvim_create_buf(v:false, v:true)
  let rimecmd_win = nvim_open_win(
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

  function! DrawCursorExtmark() abort closure
    let text_cursor = nvim_win_get_cursor(text_win)
    let col = a:append
      \ ? NextCol(nvim_win_get_buf(text_win), text_cursor) 
      \ : text_cursor[1]
    return nvim_buf_set_extmark(
      \ nvim_win_get_buf(text_win),
      \ s:extmark_ns,
      \ text_cursor[0] - 1,
      \ col, {
        \ 'virt_text': [['　', 'CursorIM']],
        \ 'virt_text_pos': 'overlay',
        \ 'hl_mode': 'combine',
      \ }
    \ )
  endfunction

  let extmark_id = DrawCursorExtmark()

  function! OnStdout(job_id, data, event) abort closure
    let commit_string = a:data[0]
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if commit_string ==# ''
      return
    endif
    call nvim_set_current_win(text_win)
    call nvim_buf_del_extmark(
      \ nvim_win_get_buf(text_win),
      \ s:extmark_ns,
      \ extmark_id
    \ )
    let text_cursor = nvim_win_get_cursor(text_win)
    let col = a:append
      \ ? NextCol(nvim_win_get_buf(text_win), text_cursor) 
      \ : text_cursor[1]
    call nvim_buf_set_text(
      \ nvim_win_get_buf(text_win),
      \ text_cursor[0] - 1,
      \ col,
      \ text_cursor[0] - 1,
      \ col,
      \ [commit_string],
    \ )
    let text_cursor[1] += strlen(commit_string)
    call nvim_win_set_cursor(text_win, text_cursor)
    call nvim_win_set_config(rimecmd_win, {
      \ 'relative': 'cursor',
      \ 'row': 1,
      \ 'col': 0,
    \ })
    call nvim_buf_del_extmark(
      \ nvim_win_get_buf(text_win),
      \ s:extmark_ns,
      \ extmark_id
    \ )
    let extmark_id = DrawCursorExtmark()
    call nvim_set_current_win(rimecmd_win)
  endfunction
  " neovim has a bug. It treats data written to tty but not stdout
  " as data written to stdout. In other words, it treats all the output
  " used to draw the Rime menu as if they are written to stdout.
  " Therefore, we have to have this workaround to collect the real stdout
  " of rimecmd.
  let fifo_filename = tempname()
  function! OnExit(job_id, data, event) abort closure
    call nvim_win_close(rimecmd_win, v:true)
    call nvim_buf_del_extmark(
      \ nvim_win_get_buf(text_win),
      \ s:extmark_ns,
      \ extmark_id
    \ )
    call jobstart(
      \ ['rm', '-f', fifo_filename],
      \ { 'detach': v:true },
    \ )
    call nvim_set_current_win(text_win)
  endfunction
  let stdout_read_job_id = jobstart(
    \ printf("mkfifo %s && cat %s", fifo_filename, fifo_filename),
    \ {
      \ "on_stdout": function('OnStdout') 
    \ },
  \ )
  let rimecmd_job_id = termopen(
    \ printf("rimecmd %s > %s", a:oneshot ? "" : "--continue", fifo_filename),
    \ {
      \ 'on_exit': function('OnExit')
    \ }
  \ )
  if rimecmd_job_id == -1
    call nvim_win_close(rimecmd_win)
    echoerr "Cannot execute rimecmd. Is it available through your PATH?" 
  endif
  startinsert
endfunction

command! Rimecmd call Rimecmd(v:false, v:false)
command! RimecmdAppend call Rimecmd(v:false, v:true)
command! RimecmdOneshot call Rimecmd(v:true, v:false)
command! RimecmdOneshotAppend call Rimecmd(v:true, v:true)
