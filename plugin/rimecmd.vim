let s:extmark_ns = nvim_create_namespace('rimecmd')
let s:rimecmd = #{ active: v:false }
let s:rimecmd_mode = #{ active: v:false }

function! s:rimecmd_mode.OnModeChangedI() abort dict
  call nvim_feedkeys("\<ESC>", 'n', v:true)
  call s:rimecmd.Enter(v:false, v:false, v:true)
endfunction

function! s:rimecmd_mode.Toggle() abort dict
  if !self.active
    let self.active = v:true
    function! OnModeChangedI() abort closure
      call self.OnModeChangedI()
    endfunction
    augroup rimecmd_mode
      autocmd!
      autocmd ModeChanged *:i call OnModeChangedI()
    augroup END
    " If user presses a/A, the cursor is by neovim placed at the append position,
    " so here append = v:false can be used.
    call s:rimecmd.Enter(v:false, v:false, v:false)
    call nvim_set_current_win(s:rimecmd.mem_var.text_win)
  else
    if s:rimecmd.active
      call s:rimecmd.Stop()
    endif
    augroup rimecmd_mode
      autocmd!
    augroup END
    let self.active = v:false
  endif
endfunction

function! s:rimecmd.OnModeChangedN() abort dict
  call nvim_set_current_win(self.mem_var.text_win)
  if exists("self.mem_var.cursor_extmark_id")
    call nvim_buf_del_extmark(
      \ nvim_win_get_buf(self.mem_var.text_win),
      \ s:extmark_ns,
      \ self.mem_var.cursor_extmark_id,
    \ )
  endif
endfunction

function! s:rimecmd.OnCursorMoved() abort dict
  let cursor_win = nvim_get_current_win()
  if cursor_win != self.mem_var.rimecmd_win
    \ && nvim_win_is_valid(self.mem_var.rimecmd_win)
    call self.ReconfigureWindow()
  endif
endfunction

function! s:rimecmd.OnCursorMovedI() abort dict
  call self.OnCursorMoved()
endfunction

function! s:rimecmd.DetermineAppend(append) abort dict
  let text_cursor = nvim_win_get_cursor(self.mem_var.text_win)
  " When cursor is at the end of the line, of course insert is meaningless.
  " In this case, append should always be true.
  let self.mem_var.append = text_cursor[1] == strlen(nvim_buf_get_lines(
    \ nvim_win_get_buf(self.mem_var.text_win),
    \ text_cursor[0] - 1,
    \ text_cursor[0],
    \ v:true,
  \ )[0])
  \ || a:append
endfunction

function! s:rimecmd.Enter(oneshot, append, start_inserting) abort dict
  if self.active
    if a:oneshot
      " If user asks for oneshot, kill the current job and let
      " the flow go back to the usual oneshot setup
      call self.Stop()
    else
      call self.DetermineAppend(a:append)
      call self.DrawCursorExtmark()
      call self.ReconfigureWindow()
      call nvim_set_current_win(self.mem_var.rimecmd_win)
      if a:start_inserting
        call nvim_feedkeys("i", 'n', v:true)
      endif
      return
    endif
  endif
  let self.active = v:true
  let rimecmd_buf = nvim_create_buf(v:false, v:true)
  let self.mem_var = #{
    \ text_win: nvim_get_current_win(),
    \ append: a:append,
    \ rimecmd_win: nvim_open_win(
      \ rimecmd_buf, v:true, {
        \ 'relative': 'cursor',
        \ 'row': 1,
        \ 'col': 2,
        \ 'height': 10,
        \ 'width': 40,
        \ 'focusable': v:true,
        \ 'border': 'single',
        \ 'title': 'rimecmd window',
        \ 'noautocmd': v:true,
      \ },
    \ ),
  \ }
  let text_cursor = nvim_win_get_cursor(self.mem_var.text_win)
  call self.DetermineAppend(a:append)
  if a:start_inserting
    call self.DrawCursorExtmark()
  endif
  call self.SetupTerm(a:oneshot)
  call nvim_set_current_win(self.mem_var.rimecmd_win)
  function! OnCursorMoved() abort closure
    call self.OnCursorMoved()
  endfunction
  function! OnCursorMovedI() abort closure
    call self.OnCursorMovedI()
  endfunction
  function! OnQuitPre() abort closure
    if nvim_get_current_win() == self.mem_var.rimecmd_win
      call self.Stop()
    endif
  endfunction
  function! OnModeChangedN() abort closure
    call self.OnModeChangedN()
  endfunction
  augroup rimecmd
    autocmd CursorMoved * call OnCursorMoved()
    autocmd CursorMovedI * call OnCursorMovedI()
    autocmd QuitPre * call OnQuitPre()
    autocmd ModeChanged t:nt call OnModeChangedN()
  augroup END
  if a:start_inserting
    call nvim_feedkeys("i", 'n', v:true)
  endif
endfunction

function! s:rimecmd.OnExit(job_id, data, event) abort dict
  augroup rimecmd
    au!
  augroup END
  call nvim_set_current_win(self.mem_var.text_win)
  " User could manually close rimecmd_win, so this check is needed.
  if nvim_win_is_valid(self.mem_var.rimecmd_win)
    call nvim_win_close(self.mem_var.rimecmd_win, v:true)
  endif
  " When exiting happens when the cursor is not in the rimecmd window,
  " we do not have the extmark.
  if exists("self.mem_var.cursor_extmark_id")
    call nvim_buf_del_extmark(
      \ nvim_win_get_buf(self.mem_var.text_win),
      \ s:extmark_ns,
      \ self.mem_var.cursor_extmark_id,
    \ )
  endif
  unlet self.mem_var
  let self.active = v:false
endfunction

function! s:rimecmd.OnStdout(job_id, data, event) abort dict
  let commit_string = a:data[0]
  " Neovim triggers on_stdout callback with a list of an empty string
  " when it gets EOF
  if commit_string ==# ''
    return
  endif
  let text_cursor = nvim_win_get_cursor(self.mem_var.text_win)
  let col = self.mem_var.append
    \ ? s:NextCharStartingCol(
      \ nvim_win_get_buf(self.mem_var.text_win),
      \ text_cursor
    \ ) : text_cursor[1]
  call nvim_buf_set_text(
    \ nvim_win_get_buf(self.mem_var.text_win),
    \ text_cursor[0] - 1,
    \ col,
    \ text_cursor[0] - 1,
    \ col,
    \ [commit_string],
  \ )
  let text_cursor[1] += strlen(commit_string)
  call nvim_win_set_cursor(self.mem_var.text_win, text_cursor)
  call self.DrawCursorExtmark()
  call self.ReconfigureWindow()
endfunction

function! s:rimecmd.ReconfigureWindow() abort dict
  let current_win = nvim_get_current_win()
  noautocmd call nvim_set_current_win(self.mem_var.text_win)
  call nvim_win_set_config(self.mem_var.rimecmd_win, {
    \ 'relative': 'cursor',
    \ 'row': 1,
    \ 'col': 0,
  \ })
  noautocmd call nvim_set_current_win(current_win)
endfunction

function! s:rimecmd.SetupTerm(oneshot) abort dict
  let fifo_filename = tempname()

  " The reason of the fifo redirection used here is neovim's limitation. When
  " the job's process is connected to a terminal, all output are sent
  " to stdout.

  function! OnCatExit(_job_id, _data, _event) abort closure
    call jobstart(["rm", "-f", fifo_filename])
  endfunction

  function! OnMkfifoExit(_job_id, exit_code, _event) abort closure
    if a:exit_code != 0
      throw "The temporary file needed by this plugin cannot be created."
    endif
    let self.mem_var.stdout_read_job_id = jobstart(
      \ ["cat", fifo_filename],
      \ {
        \ "on_stdout": function(self.OnStdout, self),
        \ "on_exit": function('OnCatExit'),
      \ },
    \ )
  endfunction

  call jobstart(["mkfifo", fifo_filename], {
    \ "on_exit": function('OnMkfifoExit'),
  \ })

  let self.mem_var.rimecmd_job_id = termopen(
    \ ["/bin/sh", "-c", printf(
      \ "rimecmd %s > %s", a:oneshot ? "" : "--continue", fifo_filename,
    \ )],
    \ {
      \ 'on_exit': function(self.OnExit, self)
    \ }
  \ )
  if self.mem_var.rimecmd_job_id == -1
    throw "Cannot execute rimecmd. Is it available from your PATH?"
    call jobstop(self.mem_var.stdout_read_job_id)
    self.OnExit()
  endif
endfunction

function! s:rimecmd.DrawCursorExtmark() abort dict
  let text_cursor = nvim_win_get_cursor(self.mem_var.text_win)
  let extmark_start_col = self.mem_var.append
    \ ? s:NextCharStartingCol(
      \ nvim_win_get_buf(self.mem_var.text_win),
      \ text_cursor
    \ ) : text_cursor[1]
  let line_text = nvim_buf_get_lines(
    \ nvim_win_get_buf(self.mem_var.text_win),
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
      \ nvim_win_get_buf(self.mem_var.text_win),
      \ [text_cursor[0], extmark_start_col],
    \ ),
    \ 'hl_group': 'CursorIM',
  \ }
  if exists('self.mem_var.cursor_extmark_id')
    let opts['id'] = self.mem_var.cursor_extmark_id
  endif
  let self.mem_var.cursor_extmark_id = nvim_buf_set_extmark(
    \ nvim_win_get_buf(self.mem_var.text_win),
    \ s:extmark_ns,
    \ text_cursor[0] - 1,
    \ extmark_start_col,
    \ opts,
  \)
endfunction

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

function! s:rimecmd.Stop() abort dict
  let jobs = [
    \ self.mem_var.rimecmd_job_id,
    \ self.mem_var.stdout_read_job_id,
  \ ]
  call jobstop(self.mem_var.rimecmd_job_id)
  call jobwait(jobs)
endfunction

command! RimecmdInsert call s:rimecmd.Enter(v:false, v:false, v:true)
command! RimecmdAppend call s:rimecmd.Enter(v:false, v:true, v:true)
command! RimecmdOneshot call s:rimecmd.Enter(v:true, v:false, v:true)
command! RimecmdOneshotAppend call s:rimecmd.Enter(v:true, v:true, v:true)
command! RimecmdStop call s:rimecmd.Stop()
command! Rimecmd call s:rimecmd_mode.Toggle()
