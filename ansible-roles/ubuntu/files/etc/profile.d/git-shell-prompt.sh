#!\bin\sh

PS1='\[\033]0;${PWD//[^[:ascii:]]/?}\007\]' # set window title
PS1="$PS1"'\[\033[32m\]'       # change to green
PS1="$PS1"'\u@\h '             # user@host<space>
PS1="$PS1"'\[\033[33m\]'       # change to brownish yellow
PS1="$PS1"'\w'                 # current working directory

if test -f "/usr/lib/git-core/git-sh-prompt"
then
    . "/usr/lib/git-core/git-sh-prompt"
    PS1="$PS1"'\[\033[36m\]'   # change color to cyan
    PS1="$PS1"'`__git_ps1`'    # bash function
fi

PS1="$PS1"'\n'                 # new line
PS1="$PS1"'\[\033[35m\]'       # change color to purple
PS1="$PS1"'$ '                 # prompt: always $
PS1="$PS1"'\[\033[0m\]'        # change color to white
