#!\bin\sh

shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=5000
PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
