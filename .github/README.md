# linux-config... aka dotfiles
On a new linux instance, we do like so
# preinit step: install git-credential-manager from the github releases page, finding the correct link for our package type
# curl -o /tmp/gcm-release https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest
# gcm_link=$(sed -n 's/^[[:blank:]]*"browser_download_url": \("https.*.deb"\)$/\1/p' /tmp/gcm-release)
# 
# returns e.g."https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.6.0/gcm-linux_amd64.2.6.0.deb"


    echo ".conf.git/" >> .gitignore
    alias conf='git --git-dir="$HOME/.conf.git/" --work-tree=$HOME'
    conf clone https://


# do some OOBE out of box experience first actiosn, like add vscode repository on fedora
# sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
# sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
# 
    


alias conf='git --git-dir=$HOME/.conf.git --work-tree=$HOME' &amp;&amp; conf add **


[git-credential-manager](https://github.com/git-ecosystem/git-credential-manager/releases): released with git-for-windows, linux and mac binaries avail from github releases page.
[git-credential-oauth](https://github.com/hickford/git-credential-oauth/releases): packaged in many distrobutions repos.
[git-credential-libsecret](https://pkgs.org/search/?q=git-credential-libsecret): stores in Linux secret service such as GNOME Keyring or KDE Wallet. Packaged in many Linux distributions.
There are also [many platform specific helpers](https://git-scm.com/doc/credential-helpers) for keepass/lastpass/azure/netlify...etc
