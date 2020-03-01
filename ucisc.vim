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

syntax match uciscOpcode /\(^\|^[ ]\+\)[0-9A-Fa-f]\+/
highlight link uciscOpcode Function

syntax match uciscComment /#.*/
syntax match uciscComment /\/[^\/]*\//
syntax match uciscComment /'[^ ]*/
highlight link uciscComment Comment


syntax match uciscLabel /\(^\s*\)\@=[a-zA-Z_:&$@!][^ ]*:/
syntax match uciscLabel /\s\<[a-zA-Z_:&$@!][^.]*\>\(.disp\|imm\)\@=/
highlight link uciscLabel Identifier

syntax match uciscDisp /\([a-zA-Z0-9_:&$@!].\)\@=\(disp\|imm\) \@=/
highlight link uciscDisp Statement

syntax match uciscControl /^[ ]*[{}]/
syntax match uciscLabel /\(\s*\)\@=\(break\|loop\)\(.disp\|.imm\)\@=/
highlight link uciscControl Statement

syntax match uciscImmediate /\s\<\(-\)\?\(0x\)\?[0-9a-fA-F]\+\>\([/.]\|\s\|$\)\@=/
highlight link uciscImmediate Number

syntax match uciscArg /\(.\)\@=\<\(reg\|mem\|val\)\>\(\/\|\s\|$\)\@=/
highlight link uciscArg Type

syntax match uciscOption /\(.\)\@=\<\(sign\|inc\|eff\)\>\(\/\|\s\|$\)\@=/
highlight link uciscOption Define

syntax match uciscData /^[ ]*% *\([0-9a-fA-F][0-9a-fA-F][ ]*\)*/
highlight link uciscData Number


set comments-=:#
set comments+=n:#
syntax match subxCommentedCode "#? .*"  | highlight link subxCommentedCode CommentedCode
let b:cmt_head = "#? "

let &cpo = s:save_cpo
