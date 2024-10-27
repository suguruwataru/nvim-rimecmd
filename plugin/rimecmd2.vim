let s:rimecmd_mode = #{ active: v:false }

function! GetMenuPageSize() abort
  let record = #{ }

  function! OnStdout(job_id, data, _event) abort dict closure
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
      \ on_stdout: function('OnStdout'),
    \ })

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
    let self.active = v:true
    call self.Enter()
  else
    call self.Exit()
  endif
endfunction

function! s:rimecmd_mode.Enter() abort dict
  let self.members = #{ }
  echom GetMenuPageSize()
  throw "not implemented"
endfunction

function! s:rimecmd_mode.Exit() abort dict
  throw "not implemented"
endfunction

command! Rimecmd call s:rimecmd_mode.Toggle()
