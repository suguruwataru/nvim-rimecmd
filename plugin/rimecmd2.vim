let s:extmark_ns = nvim_create_namespace('rimecmd')
let s:rimecmd_mode = #{ active: v:false }

function! s:NextCharStartingCol(buf, cursor) abort
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

function! s:GetMenuPageSize() abort
  let record = #{ }

  function! GetMenuPageSizeOnStdout(job_id, data, _event) abort closure
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if a:data[0] == ''
      return
    endif
    let reply = json_decode(a:data[0])
    if exists('reply.outcome')
      let record.value = reply.outcome.config_value_integer
    endif
    if exists('reply.error')
      echoerr "rimecmd --json returned error"
      throw reply.error.message
    endif
    call jobstop(a:job_id)
  endfunction

  function! RunProcess() abort
    let get_height_job_id = jobstart(["rimecmd", "--json"], #{
      \ on_stdout: function('GetMenuPageSizeOnStdout'),
    \ })
    if get_height_job_id == -1
      throw "Cannot execute rimecmd. Is it available from your PATH?"
    endif

    call chansend(get_height_job_id, json_encode(#{
      \ id: tempname(),
      \ call: #{
        \ method: "config_value_integer",
        \ params: #{ config_id: "default", option_key: "menu/page_size" },
      \ }
    \ }))
    call jobwait([get_height_job_id])
  endfunction

  call RunProcess()
  return record.value
endfunction!

function! s:rimecmd_mode.Toggle() abort dict
  if !self.active
    call self.Enter()
  else
    call self.Exit()
  endif
endfunction

function! s:rimecmd_mode.DrawCursorExtmark() abort dict
  let text_cursor = nvim_win_get_cursor(self.members.text_win)
  let extmark_start_col = text_cursor[1]
  let line_text = nvim_buf_get_lines(
    \ nvim_win_get_buf(self.members.text_win),
    \ text_cursor[0] - 1,
    \ text_cursor[0],
    \ v:true,
  \ )[0]
  let opts = extmark_start_col == strlen(line_text) ? {
    \ 'virt_text': [['　', 'CursorIM']],
    \ 'virt_text_pos': 'overlay',
  \ } : {
    \ 'end_row': text_cursor[0] - 1,
    \ 'end_col': s:NextCharStartingCol(
      \ nvim_win_get_buf(self.members.text_win),
      \ [text_cursor[0], extmark_start_col],
    \ ),
    \ 'hl_group': 'CursorIM',
  \ }
  if exists('self.members.cursor_extmark_id')
    let opts['id'] = self.members.cursor_extmark_id
  endif
  let self.members.cursor_extmark_id = nvim_buf_set_extmark(
    \ nvim_win_get_buf(self.members.text_win),
    \ s:extmark_ns,
    \ text_cursor[0] - 1,
    \ extmark_start_col,
    \ opts,
  \ )
endfunction

function! s:rimecmd_mode.ReconfigureWindow() abort dict
  let current_win = nvim_get_current_win()
  noautocmd call nvim_set_current_win(self.members.text_win)
  let win_config = {
    \ 'relative': 'cursor',
    \ 'row': 1,
    \ 'col': 0,
  \ }
  call nvim_win_set_config(self.members.rimecmd_win, win_config)
  noautocmd call nvim_set_current_win(current_win)
endfunction

function! s:rimecmd_mode.SetupTerm() abort dict
  " The reason of the fifo redirection used here is neovim's limitation. When
  " the job's process is connected to a terminal, all output are sent
  " to stdout. As a result, redirection is used to separate actual stdout
  " from terminal control output.
  let stdout_fifo = tempname()

  function! SetupTermOnStdout(_job_id, data, _event) abort closure
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if a:data[0] == ''
      return
    endif
    let commit_string = a:data[0]
    let text_cursor = nvim_win_get_cursor(self.members.text_win)
    let row = text_cursor[0] - 1
    let col = text_cursor[1]
    call nvim_buf_set_text(
      \ nvim_win_get_buf(self.members.text_win),
      \ row,
      \ col,
      \ row,
      \ col,
      \ [commit_string],
    \ )
    let text_cursor[1] += strlen(commit_string)
    call nvim_win_set_cursor(self.members.text_win, text_cursor)
    call self.DrawCursorExtmark()
    call self.ReconfigureWindow()
  endfunction

  function! OnCatExit(_job_id, _data, _event) abort closure
    call jobstart(["rm", "-f", stdout_fifo])
  endfunction

  function! OnMkfifoStdoutFifoExit(_job_id, exit_code, _event) abort closure
    call nvim_set_current_win(self.members.rimecmd_win)
    let self.members.rimecmd_job_id = termopen(
      \ ["sh", "-c", printf("rimecmd --continue > %s", stdout_fifo)],
    \ )
    if self.members.rimecmd_job_id == -1
      throw "cannot execute rimecmd"
    endif
    let self.members.stdout_read_job_id = jobstart(
      \ ["cat", stdout_fifo],
      \ #{
        \ on_stdout: function('SetupTermOnStdout'),
        \ on_exit: function('OnCatExit'),
      \ },
    \ )
    if self.members.stdout_read_job_id == -1
      throw "cannot read rimecmd's output"
    endif
    startinsert
  endfunction

  call jobstart(["mkfifo", stdout_fifo], {
    \ "on_exit": function('OnMkfifoStdoutFifoExit'),
  \ })
endfunction

function! s:rimecmd_mode.OpenWindow() abort dict
  let self.members.rimecmd_win = nvim_open_win(
    \ self.members.rimecmd_buf, v:true, {
      \ 'relative': 'cursor',
      \ 'row': 1,
      \ 'col': 2,
      \ 'height': s:GetMenuPageSize() + 1,
      \ 'width': 40,
      \ 'focusable': v:true,
      \ 'border': 'single',
      \ 'title': 'rimecmd window',
      \ 'noautocmd': v:true,
    \ },
  \ )
endfunction

function! s:rimecmd_mode.Enter() abort dict
  let self.active = v:true
  let rimecmd_buf = nvim_create_buf(v:false, v:true)
  let self.members = #{
    \ text_win: nvim_get_current_win(),
    \ rimecmd_buf: rimecmd_buf,
  \ }
  call self.DrawCursorExtmark()
  call self.OpenWindow()
  call self.SetupTerm()
endfunction

function! s:rimecmd_mode.ShowWindow() abort dict
  if exists('self.members.rimecmd_win') || !exists('self.members.rimecmd_buf')
    return
  endif
  call self.OpenWindow()
endfunction

function! s:rimecmd_mode.HideWindow() abort dict
  if exists('self.members.rimecmd_win')
    call nvim_win_hide(self.members.rimecmd_win)
    unlet self.members.rimecmd_win
  endif
  call nvim_buf_del_extmark(
    \ nvim_win_get_buf(self.members.text_win),
    \ s:extmark_ns,
    \ self.members.cursor_extmark_id,
  \ )
endfunction

function! s:rimecmd_mode.Exit() abort dict
  call nvim_set_current_win(self.members.text_win)
  if exists('self.members.rimecmd_job_id')
    call jobstop(self.members.rimecmd_job_id)
    call jobwait([self.members.rimecmd_job_id])
  endif
  call nvim_win_close(self.members.rimecmd_win, v:true)
  call nvim_buf_delete(self.members.rimecmd_buf, #{force: v:true})
  call nvim_buf_del_extmark(
    \ nvim_win_get_buf(self.members.text_win),
    \ s:extmark_ns,
    \ self.members.cursor_extmark_id,
  \ )
  unlet self.members
  let self.active = v:false
endfunction

command! Rimecmd call s:rimecmd_mode.Toggle()
command! RimecmdHide call s:rimecmd_mode.HideWindow()
command! RimecmdShow call s:rimecmd_mode.ShowWindow()
