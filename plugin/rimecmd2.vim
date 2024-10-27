let s:extmark_ns = nvim_create_namespace('rimecmd')
let s:rimecmd_mode = #{
  \ active: v:false,
  \ no_pending_input: v:true,
  \ term_already_setup: v:false,
\ }

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

function! s:PrevCharStartingCol(buf, cursor) abort
  let line_text = nvim_buf_get_lines(
    \ a:buf,
    \ a:cursor[0] - 1,
    \ a:cursor[0],
    \ v:true,
  \ )[0]
  return byteidx(
    \ line_text,
    \ charidx(line_text, max([a:cursor[1] - 1, 0])),
  \ )
endfunction

function! s:GetMenuPageSize() abort
  let record = #{ }

  function! s:GetMenuPageSizeOnStdout(job_id, data, _event) abort closure
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if a:data[0] ==# ''
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

  function! s:RunProcess() abort
    let get_height_job_id = jobstart(["rimecmd", "--json"], #{
      \ on_stdout: function('s:GetMenuPageSizeOnStdout'),
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

  call s:RunProcess()
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

function! s:rimecmd_mode.BackspaceWhenNoPendingInput() abort dict
  let current_win = nvim_get_current_win()
  noautocmd call nvim_set_current_win(self.members.text_win)
  let text_cursor = nvim_win_get_cursor(self.members.text_win)
  if text_cursor[1] > 0
    let buf = nvim_win_get_buf(self.members.text_win)
    let row = text_cursor[0] - 1
    let start_col = s:PrevCharStartingCol(buf, text_cursor)
    call nvim_buf_set_text(
      \ buf,
      \ row,
      \ start_col,
      \ row,
      \ s:NextCharStartingCol(buf, [text_cursor[0], start_col]),
      \ [''],
    \ )
  elseif text_cursor[0] > 1
    let buf = nvim_win_get_buf(self.members.text_win)
    let prev_row = text_cursor[0] - 2
    let cursor_row = text_cursor[0] - 1
    let cursor_line_text = nvim_buf_get_lines(
      \ buf,
      \ cursor_row,
      \ cursor_row + 1,
      \ v:true
    \ )[0]
    let prev_line_length = strlen(nvim_buf_get_lines(
      \ buf,
      \ prev_row,
      \ prev_row + 1,
      \ v:true
    \ )[0])
    call nvim_buf_set_text(
      \ buf,
      \ prev_row,
      \ prev_line_length,
      \ cursor_row,
      \ strlen(cursor_line_text),
      \ [cursor_line_text],
    \ )
    call nvim_win_set_cursor(
      \ self.members.text_win,
      \ [text_cursor[0] - 1, prev_line_length]
    \ )
  endif
  noautocmd call nvim_set_current_win(current_win)
  call self.DrawCursorExtmark()
  call self.ReconfigureWindow()
endfunction

function! s:rimecmd_mode.CommitString(commit_string) abort dict
  let text_cursor = nvim_win_get_cursor(self.members.text_win)
  let row = text_cursor[0] - 1
  let col = text_cursor[1]
  call nvim_buf_set_text(
    \ nvim_win_get_buf(self.members.text_win),
    \ row,
    \ col,
    \ row,
    \ col,
    \ [a:commit_string],
  \ )
  let text_cursor[1] += strlen(a:commit_string)
  call nvim_win_set_cursor(self.members.text_win, text_cursor)
  let self.no_pending_input = v:true
endfunction

function! s:rimecmd_mode.SetupTerm() abort dict
  if self.term_already_setup
    return
  endif

  let self.term_already_setup = v:true
  " The reason of the fifo redirection used here is neovim's limitation. When
  " the job's process is connected to a terminal, all output are sent
  " to stdout. As a result, redirection is used to separate actual stdout
  " from terminal control output.
  let stdout_fifo = tempname()
  let stdin_fifo = tempname()
  " The key event is directly passed to the terminal window. In order to
  " get what the key event is, and handle properly Enter and Backspace events
  " that happen when there isn't pending input for Rime, we check the requests
  " also
  let request_fifo = tempname()

  function! OnPipedRimecmdStdout(_job_id, data, _event) abort closure
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if a:data[0] ==# ''
      return
    endif
    let decoded_json = json_decode(a:data[0])
    if exists(
      \ "decoded_json.outcome.effect.update_ui.composition.length"
    \ )
      let self.no_pending_input = 
        \ decoded_json.outcome.effect.update_ui.composition.length == 0
    endif 
    if !exists("decoded_json.outcome.effect.commit_string")
      return
    endif
    call self.CommitString(decoded_json.outcome.effect.commit_string)
    call self.DrawCursorExtmark()
    call self.ReconfigureWindow()
  endfunction

  function! OnPipedRequestStdout(_job_id, data, _event) abort closure
    " Neovim triggers on_stdout callback with a list of an empty string
    " when it gets EOF
    if a:data[0] ==# ''
      return
    endif
    let decoded_json = json_decode(a:data[0])
    if !exists("decoded_json.call.method")
    \ || decoded_json.call.method !=# "process_key"
      return
    endif
    if !exists("decoded_json.call.params.mask")
    \ || !exists("decoded_json.call.params.keycode")
      throw "Unexpected JSON format"
    endif
    if decoded_json.call.params.keycode == 65288
    \ && decoded_json.call.params.mask == 0
    \ && self.no_pending_input
      call self.BackspaceWhenNoPendingInput()
    endif
    if decoded_json.call.params.keycode == 65293
    \ && decoded_json.call.params.mask == 0
    \ && self.no_pending_input
      " TODO
      echom "enter"
    endif
  endfunction

  function! OnMkfifoStdoutFifoExit(_job_id, exit_code, _event) abort closure
    call nvim_set_current_win(self.members.rimecmd_win)
    let self.members.rimecmd_job_id = termopen(
      \ ["sh", "-c", printf(
        \ "rimecmd --duplicate-requests %s --tty --json -c < %s > %s",
        \ request_fifo,
        \ stdin_fifo,
        \ stdout_fifo,
      \ )],
      \ #{ on_exit: {-> self.Exit()} }
    \ )
    if self.members.rimecmd_job_id == -1
      throw "cannot execute rimecmd"
    endif
    let self.members.stdin_write_job_id = jobstart(
      \ ["tee", stdin_fifo],
      \ #{
        \ on_stdout: function('OnPipedRimecmdStdout'),
        \ on_exit: {-> jobstart(["rm", "-f", stdin_fifo])},
      \ },
    \ )
    if self.members.stdin_write_job_id == -1
      throw "cannot write to rimecmd's input"
    endif
    let self.members.stdout_read_job_id = jobstart(
      \ ["cat", stdout_fifo],
      \ #{
        \ on_stdout: function('OnPipedRimecmdStdout'),
        \ on_exit: {-> jobstart(["rm", "-f", stdout_fifo])},
      \ },
    \ )
    if self.members.stdout_read_job_id == -1
      throw "cannot read rimecmd's output"
    endif
    let self.members.request_read_job_id = jobstart(
      \ ["cat", request_fifo],
      \ #{
        \ on_stdout: function('OnPipedRequestStdout'),
        \ on_exit: {-> jobstart(["rm", "-f", request_fifo])},
      \ },
    \ )
    startinsert
  endfunction

  call jobstart(["sh", "-c", printf(
      \ "mkfifo %s && mkfifo %s && mkfifo %s",
      \ stdout_fifo,
      \ stdin_fifo,
      \ request_fifo,
    \ )], {
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

  augroup rimecmd_mode
    autocmd ModeChanged t:nt call s:rimecmd_mode.OnModeChangedN()
    autocmd ModeChanged *:i call s:rimecmd_mode.OnModeChangedI()
    autocmd QuitPre * call s:rimecmd_mode.OnQuitPre()
  augroup END
endfunction

function! s:rimecmd_mode.OnModeChangedI() abort dict
  if nvim_get_current_win() == self.members.text_win
    call self.ShowWindow()
  endif
endfunction

function! s:rimecmd_mode.OnQuitPre() abort dict
  if exists('self.members.rimecmd_win') &&
  \ nvim_get_current_win() == self.members.rimecmd_win
    call self.Exit()
  endif
endfunction

function! s:rimecmd_mode.OnModeChangedN() abort dict
  if nvim_get_current_win() == self.members.rimecmd_win
    call nvim_set_current_win(self.members.text_win)
    call self.HideWindow()
  endif
endfunction

function! s:rimecmd_mode.ShowWindow() abort dict
  if exists('self.members.rimecmd_win') || !exists('self.members.rimecmd_buf')
    return
  endif
  call self.OpenWindow()
  call self.SetupTerm()
  call self.ReconfigureWindow()
  call self.DrawCursorExtmark()
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
  if !self.active
    return
  endif
  let self.active = v:false
  augroup rimecmd_mode
    autocmd!
  augroup END
  call nvim_set_current_win(self.members.text_win)
  if exists('self.members.rimecmd_job_id')
    call jobstop(self.members.rimecmd_job_id)
    call jobwait([self.members.rimecmd_job_id])
  endif
  if exists('self.members.stdin_write_job_id')
    call jobstop(self.members.stdin_write_job_id)
    call jobwait([self.members.stdin_write_job_id])
  endif
  if exists('self.members.stdout_read_job_id')
    call jobstop(self.members.stdout_read_job_id)
    call jobwait([self.members.stdout_read_job_id])
  endif
  if exists('self.members.request_read_job_id')
    call jobstop(self.members.request_read_job_id)
    call jobwait([self.members.request_read_job_id])
  endif
  let self.term_already_setup = v:false
  if exists('self.members.rimecmd_win')
    call nvim_win_close(self.members.rimecmd_win, v:true)
  endif
  if exists('self.members.rimecmd_buf')
    call nvim_buf_delete(self.members.rimecmd_buf, #{force: v:true})
  endif
  call nvim_buf_del_extmark(
    \ nvim_win_get_buf(self.members.text_win),
    \ s:extmark_ns,
    \ self.members.cursor_extmark_id,
  \ )
  unlet self.members
endfunction

command! Rimecmd call s:rimecmd_mode.Toggle()
