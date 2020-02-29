" uCISC syntax file
" Language:    uCISC
" URL:         https://github.com/grokthis/ucisc-ruby
" License:     MIT
"
" Copy this into your ftplugin directory, and add the following to your vimrc
" or to .vim/ftdetect/ucisc.vim:
"   autocmd BufReadPost,BufNewFile *.ucisc set filetype=ucisc

let s:save_cpo = &cpo
set cpo&vim

" setlocal iskeyword=@,48-57,?,!,_,$,-
setlocal formatoptions-=t  " allow long lines
setlocal formatoptions+=c  " but comments should still wrap

setlocal iskeyword+=-,?,<,>

syntax match uciscComment /#.*/
syntax match uciscComment /\/[^\/]*\//
syntax match uciscComment /'[^ ]*/
highlight link uciscComment Comment

set comments-=:#
set comments+=n:#
syntax match subxCommentedCode "#? .*"  | highlight link subxCommentedCode CommentedCode
let b:cmt_head = "#? "

let &cpo = s:save_cpo
