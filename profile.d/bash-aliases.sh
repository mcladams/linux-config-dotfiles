# Check for interactive bash
if [ -n "${BASH_VERSION-}" ]; then
    if [ -f ~/.bash_aliases ]; then
        . ~/.bash_aliases
    fi
fi
