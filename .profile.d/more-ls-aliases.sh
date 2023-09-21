# Check for interactive bash
if [ -n "${BASH_VERSION-}" ]; then
    alias ll='ls -l'
    alias la='ls -A'
    alias lo='ls -o'
    alias lag='ls -laGg'
    alias l='ls -CF'
fi

