#!/usr/bin/env bash
LC_ALL=C
PACKAGE_INSTALLATION_TRIES=0
PACKAGE_INSTALLATION_COUNT=0

readonly VERSION="0.3.9"

# set a github auth token (e.g a PAT ) in DEBGET_TOKEN to get a bigger rate limit
if [ -n "${DEBGET_TOKEN}" ]; then
    export HEADERAUTH="\"Authorization: token ${DEBGET_TOKEN}\""
    export HEADERPARAM="--header"
else
    unset HEADERAUTH
    unset HEADERPARAM
fi

function usage() {
cat <<HELP

Usage

deb-get {update [--repos-only] [--quiet] | upgrade | show <pkg list> | install <pkg list>
        | reinstall <pkg list> | remove [--remove-repo] <pkg list>
        | purge [--remove-repo] <pkg list>
        | search [--include-unsupported] <regex> | cache | clean
        | list [--include-unsupported] [--raw|--installed|--not-installed]
        | prettylist [<repo>] | csvlist [<repo>] | fix-installed [--old-apps]
        | help | version}

deb-get provides a high-level commandline interface for the package management
system to easily install and update packages published in 3rd party apt
repositories or via direct download.

update
    update is used to resynchronize the package index files from their sources.
    When --repos-only is provided, only initialize and update deb-get's
    external repositories, without updating apt or looking for updates of
    installed packages.
    When --quiet is provided the fetching of deb-get repository updates is done without progress feedback.

upgrade
    upgrade is used to install the newest versions of all packages currently
    installed on the system.

install
    install is followed by one package (or a space-separated list of packages)
    desired for installation or upgrading.

reinstall
    reinstall is followed by one package (or a space-separated list of
    packages) desired for reinstallation.

remove
    remove is identical to install except that packages are removed instead of
    installed. When --remove-repo is provided, also remove the apt repository
    of apt/ppa packages.

purge
    purge is identical to remove except that packages are removed and purged
    (any configuration files are deleted too). When --remove-repo is provided,
    also remove the apt repository of apt/ppa packages.

clean
    clean clears out the local repository (/var/cache/deb-get) of retrieved
    package files.

search
    search for the given regex(7) term(s) from the list of available packages
    supported by deb-get and display matches. When --include-unsupported is
    provided, include packages with unsupported architecture or upstream
    codename and include PPAs for Debian-derived distributions.

show
    show information about the given package (or a space-separated list of
    packages) including their install source and update mechanism.

list
    list the packages available via deb-get. When no option is provided, list
    all supported packages and tell which ones are installed (slower). When
    --include-unsupported is provided, include packages with unsupported
    architecture or upstream codename and include PPAs for Debian-derived
    distributions (faster). When --raw is provided, list all packages and do
    not tell which ones are installed (faster). When --installed is provided,
    only list the packages installed (faster). When --not-installed is provided,
    only list the packages not installed (faster).

prettylist
    markdown formatted list the packages available in repo. repo defaults to
    01-main. If repo is 00-builtin or 01-main the packages from 00-builtin are
    included. Use this to update README.md.

csvlist
    csv formatted list the packages available in repo. repo defaults to
    01-main. If repo is 00-builtin or 01-main the packages from 00-builtin are
    included. Use this with 3rd party wrappers.

cache
    list the contents of the deb-get cache (/var/cache/deb-get).

fix-installed
    fix installed packages whose definitions were changed. When --old-apps is
    provided, transition packages to new format. This command is only intended
    for internal use.

help
    show this help.

version
    show deb-get version.

HELP
}

function package_is_installed() {
    if [[ " ${INSTALLED_APPS[*]} " =~ " ${1} " ]]; then return 0; fi
    return 1;
}

function elevate_privs() {
    if [ "$(id -ru)" -eq 0 ]; then
        # Alreday in the root context
        ELEVATE=""
    elif command -v doas 1>/dev/null; then
        ELEVATE="doas"
    elif command -v sudo 1>/dev/null; then
        ELEVATE="sudo"
    else
        fancy_message fatal "$(basename "${0}") requires sudo or doas to elevate permissions, neither were found."
    fi

    # Authenticate root context
    if [ -n "${ELEVATE}" ]; then
        ${ELEVATE} true
    fi
}

function create_cache_dir() {
    if [ -d /var/cache/get-deb ]; then
        ${ELEVATE} mv /var/cache/get-deb "${CACHE_DIR}"
    fi
    ${ELEVATE} mkdir -p "${CACHE_DIR}" 2>/dev/null
    ${ELEVATE} chmod 755 "${CACHE_DIR}" 2>/dev/null
}

function create_etc_dir() {
    ${ELEVATE} mkdir -p "${ETC_DIR}" 2>/dev/null
    ${ELEVATE} chmod 755 "${ETC_DIR}" 2>/dev/null
}


function unroll_url() {
    # Sourceforge started adding parameters
    local TRIM_URL="$(curl -w "%{url_effective}\n" -I -L -s -S "${1}" -o /dev/null)"
    echo "${TRIM_URL/\.deb*/.deb}"
}


function get_github_releases() {
    METHOD="github"
    CACHE_FILE="${CACHE_DIR}/${APP}.json"
    # Cache github releases json for 1 hour to try and prevent API rate limits
    #   https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting
    #   {"message":"API rate limit exceeded for 62.31.16.154. (But here's the good news: Authenticated requests get a higher rate limit. Check out the documentation for more details.)","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"}
    #   curl -I https://api.github.com/users/flexiondotorg

    # Do not process github releases while generating a pretty list or upgrading
    if [ "${ACTION}" == "install" ] || [ "${ACTION}" == "update" ] || [ "${ACTION}" == "fix-installed" ]; then
        if [ ! -e "${CACHE_FILE}" ] || test "$(find "${CACHE_FILE}" -mmin +${DEBGET_CACHE_RTN:-60})"; then
            fancy_message info "Updating ${CACHE_FILE}"
            local URL="https://api.github.com/repos/${1}/releases"
            if [ -n "${2}" ]; then
                URL+="/${2}"
            fi
            wgetcmdarray=("${ELEVATE}" wget  "${HEADERPARAM}" "${HEADERAUTH}" ${WGET_VERBOSITY} \
                --no-use-server-timestamps ${WGET_TIMEOUT} "${URL}" -O "${CACHE_FILE}")
            echo "${wgetcmdarray[@]}" | bash -  || ( fancy_message warn "Updating ${CACHE_FILE} failed." )
            if [ -f "${CACHE_FILE}" ] && grep "API rate limit exceeded" "${CACHE_FILE}"; then
                fancy_message warn "Updating ${CACHE_FILE} exceeded GitHub API limits. Deleting it."
                ${ELEVATE} rm "${CACHE_FILE}" 2>/dev/null
            fi
        fi
    fi
}

function get_website() {
    METHOD="website"
    CACHE_FILE="${CACHE_DIR}/${APP}.html"
    if [ "${ACTION}" == "install" ] || [ "${ACTION}" == "update" ] || [ "${ACTION}" == "fix-installed" ]; then
        if [ ! -e "${CACHE_FILE}" ] || test "$(find "${CACHE_FILE}" -mmin +${DEBGET_CACHE_RTN:-60})"; then
            fancy_message info "Updating ${CACHE_FILE}"
            if ! ${ELEVATE} wget ${WGET_VERBOSITY} --no-use-server-timestamps ${WGET_TIMEOUT} "${1}" -O "${CACHE_FILE}"; then
                fancy_message warn "Updating ${CACHE_FILE} failed. Deleting it."
                ${ELEVATE} rm -f "${CACHE_FILE}"
            fi
        fi
    fi
}

function fancy_message() {
    if [ -z "${1}" ] || [ -z "${2}" ]; then
      return
    fi

    local RED="\e[31m"
    local GREEN="\e[32m"
    local YELLOW="\e[33m"
    local MAGENTA="\e[35m"
    local RESET="\e[0m"
    local MESSAGE_TYPE=""
    local MESSAGE=""
    MESSAGE_TYPE="${1}"
    MESSAGE="${2}"

    case ${MESSAGE_TYPE} in
      info) echo -e "  [${GREEN}+${RESET}] ${MESSAGE}";;
      progress) echo -en "  [${GREEN}+${RESET}] ${MESSAGE}";;
      recommend) echo -e "  [${MAGENTA}!${RESET}] ${MESSAGE}";;
      warn) echo -e "  [${YELLOW}*${RESET}] WARNING! ${MESSAGE}";;
      error) echo -e "  [${RED}!${RESET}] ERROR! ${MESSAGE}" >&2;;
      fatal) echo -e "  [${RED}!${RESET}] ERROR! ${MESSAGE}" >&2
             exit 1;;
      *) echo -e "  [?] UNKNOWN: ${MESSAGE}";;
    esac
}

function download_deb() {
    local URL="${1}"
    local FILE="${2}"

    if ! ${ELEVATE} wget ${WGET_VERBOSITY} --continue ${WGET_TIMEOUT} --show-progress --progress=bar:force:noscroll "${URL}" -O "${CACHE_DIR}/${FILE}"; then
        fancy_message error "Failed to download ${URL}. Deleting ${CACHE_DIR}/${FILE}..."
        ${ELEVATE} rm "${CACHE_DIR}/${FILE}" 2>/dev/null
        return 1
    fi
}

function eula() {
    if [ -n "${EULA}" ] && [ "${DEBIAN_FRONTEND}" != noninteractive ]; then
        echo -e "${EULA}"
        echo -e "\nDo you agree to the ${APP} EULA?"
        select yn in "Yes" "No"; do
            case $yn in
                Yes) return 0;;
                No) return 1;;
            esac
        done
    fi
}

function update_apt() {
    ${ELEVATE} apt-get -q -o Dpkg::Progress-Fancy="1" -y update
}

function upgrade_apt() {
    ${ELEVATE} apt-get -q -o Dpkg::Progress-Fancy="1" -y upgrade
}

# Update only the added repo (during install action)
function update_only_repo() {
    fancy_message info "Updating: /etc/apt/sources.list.d/${APT_LIST_NAME}.list"
    ${ELEVATE} apt-get update -o Dir::Etc::sourcelist="sources.list.d/${APT_LIST_NAME}.list" \
        -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
}

function install_apt() {
    ((PACKAGE_INSTALLATION_TRIES++))
    add_apt_repo
    if ! update_only_repo; then
        remove_repo --remove-repo --quiet
        return
    fi

    if ! package_is_installed "${APP}"; then
        if ! eula; then
            remove_repo --remove-repo --quiet
            return
        fi
        if ! ${ELEVATE} apt-get -q=2 -o Dpkg::Progress-Fancy="1" -y install "${APP}"; then
            remove_repo --remove-repo --quiet
            return
        fi
        add_installed
        maint_supported_cache
    else
        if [ "${ACTION}" == "reinstall" ]; then
            if ! ${ELEVATE} apt-get -q=2 -o Dpkg::Progress-Fancy="1" -y --reinstall --allow-downgrades install "${APP}"; then
                return
            fi
        else
            fancy_message info "${APP} is up to date."
        fi
    fi
    ((PACKAGE_INSTALLATION_COUNT++))
}

function install_ppa() {
    ppa_to_apt
    install_apt
}

function install_deb() {
    local URL="${1}"
    local FILE="${FILE:-${URL##*/}}"
    local STATUS=""
    ((PACKAGE_INSTALLATION_TRIES++))

    if ! package_is_installed "${APP}"; then
        if ! eula; then
            return
        fi
        if ! download_deb "${URL}" "${FILE}"; then
            return
        fi
        if ! ${ELEVATE} apt-get -q=2 -o Dpkg::Progress-Fancy="1" -y install "${CACHE_DIR}/${FILE}"; then
            return
        fi
        add_installed
        maint_supported_cache
    else
        if [ "${ACTION}" == "reinstall" ]; then
            if ! download_deb "${URL}" "${FILE}"; then
                return
            fi
            if ! ${ELEVATE} apt-get -q=2 -o Dpkg::Progress-Fancy="1" -y --reinstall --allow-downgrades install "${CACHE_DIR}/${FILE}"; then
                return
            fi
        elif dpkg --compare-versions "${VERSION_PUBLISHED}" gt "${VERSION_INSTALLED}"; then
            if ! download_deb "${URL}" "${FILE}"; then
                return
            fi
            if ! ${ELEVATE} apt-get -q=2 -o Dpkg::Progress-Fancy="1" -y install "${CACHE_DIR}/${FILE}"; then
                return
            fi
        elif [ -z "${FILE}" ]; then
            fancy_message warn "${APP} update check failed, moving on to next package."
        else
            fancy_message info "${FILE} is up to date."
        fi
    fi
    ((PACKAGE_INSTALLATION_COUNT++))
    if [ -f "${CACHE_DIR}/${FILE}" ]; then
        ${ELEVATE} rm "${CACHE_DIR}/${FILE}" 2>/dev/null
    fi
}

function remove_deb() {
    local APP="${1}"
    local REMOVE="${2:-remove}"
    local FILE="${FILE:-${URL##*/}}"
    local STATUS=""

    if package_is_installed "${APP}" || [[ " ${DEPRECATED_INSTALLED[*]} " =~ " ${APP} " ]]; then
        STATUS="$(dpkg -s "${APP}" | grep ^Status: | cut -d" " -f2-)"
        if [ "${STATUS}" == "deinstall ok config-files" ]; then
            REMOVE="purge"
        fi
        ${ELEVATE} apt-get -q -y --autoremove ${REMOVE} "${APP}"
        remove_installed "${APP}"
        maint_supported_cache
    else
        fancy_message info "${APP} is not installed."
    fi

    # Remove repos/PPA/key even if the app is not installed.
    case ${METHOD} in
        direct|github|website)
            if [ -f "${CACHE_DIR}/${FILE}" ]; then
                fancy_message info "Removing ${CACHE_DIR}/${FILE}"
                ${ELEVATE} rm "${CACHE_DIR}/${FILE}" 2>/dev/null
            fi
            ;;
        apt|ppa)
            remove_repo "${3}";;
    esac

}

function version_deb() {
    if package_is_installed "${APP}"; then
        dpkg -s "${APP}" 2> /dev/null | grep ^Version: | cut -d' ' -f2
    else
        echo ""
    fi
}

function info_deb() {
    local INSTALLED="${VERSION_INSTALLED:-No}"
    case ${METHOD} in
        direct|github|website) echo -e "${PRETTY_NAME}\n  Package:\t${APP}\n  Repository:\t${APP_SRC}\n  Updater:\tdeb-get\n  Installed:\t${INSTALLED}\n  Published:\t${VERSION_PUBLISHED}\n  Architecture:\t${ARCHS_SUPPORTED}\n  Download:\t${URL}\n  Website:\t${WEBSITE}\n  Summary:\t${SUMMARY}";;
        apt) echo -e "${PRETTY_NAME}\n  Package:\t${APP}\n  Repository:\t${APP_SRC}\n  Updater:\tapt\n  Installed:\t${INSTALLED}\n  Architecture:\t${ARCHS_SUPPORTED}\n  Repository:\t${APT_REPO_URL}\n  Website:\t${WEBSITE}\n  Summary:\t${SUMMARY}";;
        ppa) echo -e "${PRETTY_NAME}\n  Package:\t${APP}\n  Repository:\t${APP_SRC}\n  Updater:\tapt\n  Installed:\t${INSTALLED}\n  Architecture:\t${ARCHS_SUPPORTED}\n  Launchpad:\t${PPA}\n  Website:\t${WEBSITE}\n  Summary:\t${SUMMARY}";;
    esac
}

function validate_deb() {
    local FULL_APP="${1}"
    export APP_SRC="$(echo "${FULL_APP}" | cut -d / -f 1)"
    export APP="$(echo "${FULL_APP}" | cut -d / -f 2)"
    export DEFVER=""
    export ASC_KEY_URL=""
    export GPG_KEY_URL=""
    export GPG_KEY_ID=""
    export APT_LIST_NAME="${APP}"
    export APT_REPO_URL=""
    export APT_REPO_OPTIONS=""
    export PPA=""
    export ARCHS_SUPPORTED="amd64"
    export CODENAMES_SUPPORTED=""
    export METHOD="direct"
    export EULA=""
    export CACHE_FILE=""
    export URL=""
    export VERSION_INSTALLED=""
    export VERSION_PUBLISHED=""
    export PRETTY_NAME=""
    export SUMMARY=""
    export WEBSITE=""
    export FILE=""

    # Source the variables
    if [ "${APP_SRC}" == "00-builtin" ]; then
        deb_"${APP}" 2>/dev/null
    else
        . "${ETC_DIR}/${APP_SRC}.d/${APP}" 2>/dev/null
    fi
    if [[ " ${ARCHS_SUPPORTED} " =~ " ${HOST_ARCH} " ]] && { [ -z "${CODENAMES_SUPPORTED}" ] || [[ " ${CODENAMES_SUPPORTED} " =~ " ${UPSTREAM_CODENAME} " ]]; } && { [ "${METHOD}" != ppa ] || [ "${UPSTREAM_ID}" == ubuntu ]; }; then

        if [ -z "${DEFVER}" ] || [ -z "${PRETTY_NAME}" ] || [ -z "${SUMMARY}" ] || [ -z "${WEBSITE}" ]; then
            fancy_message error "Missing required information of package ${APP}:"
            echo "DEFVER=${DEFVER}" >&2
            echo "PRETTY_NAME=${PRETTY_NAME}" >&2
            echo "SUMMARY=${SUMMARY}" >&2
            echo "WEBSITE=${WEBSITE}" >&2
            exit 1
        fi
        VERSION_INSTALLED=$(version_deb)
        if [ -n "${APT_REPO_URL}" ]; then
            METHOD="apt"
            if [ "${ACTION}" != "prettylist" ]; then
                if [ -z "${ASC_KEY_URL}" ] && [ -z "${GPG_KEY_URL}" ] && [ -z "${GPG_KEY_ID}" ]; then
                    fancy_message error "Missing required information of apt package ${APP}:"
                    echo "ASC_KEY_URL=${ASC_KEY_URL}" >&2
                    echo "GPG_KEY_URL=${GPG_KEY_URL}" >&2
                    echo "GPG_KEY_ID=${GPG_KEY_ID}" >&2
                    exit 1
                fi
                if [ -n "${ASC_KEY_URL}" ] && [ -n "${GPG_KEY_URL}" ]; then
                    fancy_message error "Conflicting repository key types for apt package ${APP}:"
                    echo "ASC_KEY_URL=${ASC_KEY_URL}" >&2
                    echo "GPG_KEY_URL=${GPG_KEY_URL}" >&2
                    echo "GPG_KEY_ID=${GPG_KEY_ID}" >&2
                    exit 1
                fi
                if [ -n "${GPG_KEY_URL}" ] && [ -n "${GPG_KEY_ID}" ]; then
                    fancy_message error "Conflicting repository key types for apt package ${APP}:"
                    echo "ASC_KEY_URL=${ASC_KEY_URL}" >&2
                    echo "GPG_KEY_URL=${GPG_KEY_URL}" >&2
                    echo "GPG_KEY_ID=${GPG_KEY_ID}" >&2
                    exit 1
                fi
                if [ -n "${ASC_KEY_URL}" ] && [ -n "${GPG_KEY_ID}" ]; then
                    fancy_message error "Conflicting repository key types for apt package ${APP}:"
                    echo "ASC_KEY_URL=${ASC_KEY_URL}" >&2
                    echo "GPG_KEY_URL=${GPG_KEY_URL}" >&2
                    echo "GPG_KEY_ID=${GPG_KEY_ID}" >&2
                    exit 1
                fi
            fi
        elif [ -n "${PPA}" ]; then
            METHOD="ppa"
        else
            # If the method is github and the cache file is empty, ignore the package
            # The GitHub API is rate limit has likely been reached
            if [ "${METHOD}" == github ] && [ ! -s "${CACHE_FILE}" ]; then
                if [ "${ACTION}" != "prettylist" ] && [ "${ACTION}" != "remove" ] && [ "${ACTION}" != "purge" ]; then
                    fancy_message warn "Cached file ${CACHE_FILE} is empty or missing."
                    ${ELEVATE} rm "${CACHE_FILE}" 2>/dev/null
                fi
            fi

            if { { { [ "${METHOD}" == github ] || [ "${METHOD}" == website ]; } && [ -s "${CACHE_FILE}" ]; } || [ "${METHOD}" == direct ]; } &&
            { [ "${ACTION}" != "prettylist" ] && [ "${ACTION}" != "remove" ] && [ "${ACTION}" != "purge" ]; } &&
            { [ -z "${URL}" ] || [ -z "${VERSION_PUBLISHED}" ]; }; then
                fancy_message error "Missing required information of ${METHOD} package ${APP}:"
                echo "URL=${URL}" >&2
                echo "VERSION_PUBLISHED=${VERSION_PUBLISHED}" >&2
                exit 1
            fi
        fi
    elif [ -n "${PPA}" ]; then
        METHOD="ppa"
    else
        # If the method is github and the cache file is empty, ignore the package
        # The GitHub API is rate limit has likely been reached
        if [ "${METHOD}" == github ] && [ ! -s "${CACHE_FILE}" ]; then
            if [ "${ACTION}" != "prettylist" ] && [ "${ACTION}" != "remove" ] && [ "${ACTION}" != "purge" ]; then
                fancy_message warn "Cached file ${CACHE_FILE} is empty or missing."
                ${ELEVATE} rm "${CACHE_FILE}" 2>/dev/null
            fi
        fi

        if { { { [ "${METHOD}" == github ] || [ "${METHOD}" == website ]; } && [ -s "${CACHE_FILE}" ]; } || [ "${METHOD}" == direct ]; } &&
           { [ "${ACTION}" != "prettylist" ] && [ "${ACTION}" != "remove" ] && [ "${ACTION}" != "purge" ]; } &&
           { [ -z "${URL}" ] || [ -z "${VERSION_PUBLISHED}" ]; } &&
           { [ -z "${ARCHS_SUPPORTED}" ] || [[ " ${ARCHS_SUPPORTED} " =~ " ${HOST_ARCH} " ]]; } &&
           { [ -z "${CODENAMES_SUPPORTED}" ] || [[ " ${CODENAMES_SUPPORTED} " =~ " ${UPSTREAM_CODENAME} " ]]; }; then
            fancy_message error "Missing required information of ${METHOD} package ${APP}:"
            echo "URL=${URL}" >&2
            echo "VERSION_PUBLISHED=${VERSION_PUBLISHED}" >&2
            exit 1
        fi
    fi
}

function list_debs() {
    if [ "${1}" == --include-unsupported ]; then
        if [ "${2}" = --raw ]; then
            local OLD_IFS="$IFS"
            IFS=$'\n'
            echo "${APPS[*]}" | cut -d / -f 2
            IFS="$OLD_IFS"
        elif [ "${2}" = --installed ]; then
            local OLD_IFS="$IFS"
            IFS=$'\n'
            echo "${INSTALLED_APPS[*]}"
            IFS="$OLD_IFS"
        elif [ "${2}" = --not-installed ]; then
            local NOT_INSTALLED_APPS=($(IFS=$'\n'; echo "${APPS[*]}" | cut -d / -f 2))

            for APP in ${INSTALLED_APPS[@]}; do
                for i in "${!NOT_INSTALLED_APPS[@]}"; do
                    if [[ ${NOT_INSTALLED_APPS[i]} = $APP ]]; then
                    unset 'NOT_INSTALLED_APPS[i]'
                    fi
                done
            done

            local OLD_IFS="$IFS"
            IFS=$'\n'
            echo "${NOT_INSTALLED_APPS[*]}"
            IFS="$OLD_IFS"
        else
            local PAD='                              '
            for FULL_APP in "${APPS[@]}"; do
                local APP="$(echo "${FULL_APP}" | cut -d / -f 2)"
                if package_is_installed "${APP}"; then
                    printf "%s %s [ installed ]\n" "${APP}" "${PAD:${#APP}}"
                else
                    echo "${APP}"
                fi
            done
        fi
    else
        if [ -f ${CACHE_DIR}/supported.list ] ; then
            if [ "${2}" == --raw ]; then
                list_debs --include-unsupported --raw | comm --nocheck-order -12 ${CACHE_DIR}/supported_apps.list -
            elif [ "${2}" == --installed ]; then
                # these don't have the [installed] tag so need a similar file to join
                list_debs --include-unsupported --installed | comm  --nocheck-order -12 ${CACHE_DIR}/supported_apps.list -
            elif [ "${2}" == --not-installed ]; then
                list_debs --include-unsupported --not-installed | comm --nocheck-order -12 ${CACHE_DIR}/supported_apps.list -
            elif [ "${2}" == --only-unsupported ]; then
                list_debs --include-unsupported --raw | comm --nocheck-order -13 ${CACHE_DIR}/supported_apps.list -
            else
                # this has [ installed ] tags
                list_debs --include-unsupported  | comm --nocheck-order -12 ${CACHE_DIR}/supported.list -
            fi
        else
            #elevate_privs
            # because we need to update the cache files this one slow time
            for FULL_APP in "${APPS[@]}"; do
                validate_deb "${FULL_APP}"
                if [[ " ${ARCHS_SUPPORTED} " =~ " ${HOST_ARCH} " ]] && { [ -z "${CODENAMES_SUPPORTED}" ] || [[ " ${CODENAMES_SUPPORTED} " =~ " ${UPSTREAM_CODENAME} " ]]; } && { [ "${METHOD}" != ppa ] || [ "${UPSTREAM_ID}" == ubuntu ]; }; then
                    if [ "${2}" == --raw ]; then
                        echo "${APP}"
                    elif [ "${2}" == --installed ]; then
                        if package_is_installed "${APP}"; then
                            echo "${APP}"
                        fi
                    elif [ "${2}" == --not-installed ]; then
                        if ! package_is_installed "${APP}"; then
                            echo "${APP}"
                        fi
                    else
                        if package_is_installed "${APP}"; then
                            local PAD='                              '
                            printf "%s %s [ installed ]\n" "${APP}" "${PAD:${#APP}}"
                        else
                            echo "${APP}"
                        fi
                    fi
                fi

            done
        fi
    fi
}

function prettylist_debs() {
    local REPO="${1:-01-main}"
    local ICON=""
    echo "| Source   | Package Name   | Description   |
| :------: | :------------- | :------------ |"
    for FULL_APP in "${APPS[@]}"; do
        validate_deb "${FULL_APP}"
        if [ "${APP_SRC}" == "${REPO}" ] || { [ "${REPO}" == "01-main" ] && [ "${APP_SRC}" == "00-builtin" ]; }; then
            case ${METHOD} in
                apt)    ICON="debian.png";;
                github) ICON="github.png";;
                ppa)    ICON="launchpad.png";;
                *)      ICON="direct.png";;
            esac
            echo "| [<img src=\"../.github/${ICON}\" align=\"top\" width=\"20\" />](${WEBSITE}) | "'`'"${APP}"'`'" | <i>${SUMMARY}</i> |"
        fi
    done
}

function csvlist_debs() {
    local REPO="${1:-01-main}"
    for FULL_APP in "${APPS[@]}"; do
        validate_deb "${FULL_APP}"
        if [ "${APP_SRC}" == "${REPO}" ] || { [ "${REPO}" == "01-main" ] && [ "${APP_SRC}" == "00-builtin" ]; }; then
            echo "\"${APP}\",\"${PRETTY_NAME}\",\"${VERSION_INSTALLED}\",\"${ARCHS_SUPPORTED}\",\"${METHOD}\",\"${SUMMARY}\""
        fi
    done
}

function update_debs() {
    local STATUS=""
    update_apt
    for APP in "${INSTALLED_APPS[@]}"; do
        validate_deb "$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
        if [ "${METHOD}" == "direct" ] || [ "${METHOD}" == "github" ] || [ "${METHOD}" == "website" ]; then
            STATUS="$(dpkg -s "${APP}" | grep ^Status: | cut -d" " -f2-)"
            if [ "${STATUS}" == "install ok installed" ] && dpkg --compare-versions "${VERSION_PUBLISHED}" gt "${VERSION_INSTALLED}"; then
                fancy_message info "${APP} (${VERSION_INSTALLED}) has an update pending. ${VERSION_PUBLISHED} is available."
            fi
        fi
    done
}

function upgrade_debs() {
    local STATUS=""
    upgrade_apt
    for APP in "${INSTALLED_APPS[@]}"; do
        validate_deb "$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
        if [ "${METHOD}" == "direct" ] || [ "${METHOD}" == "github" ] || [ "${METHOD}" == "website" ]; then
            STATUS="$(dpkg -s "${APP}" | grep ^Status: | cut -d" " -f2-)"
            if [ "${STATUS}" == "install ok installed" ]; then
                install_deb "${URL}"
            fi
        fi
    done
}

function init_repos() {
    if [ ! -e "${ETC_DIR}/01-main.repo" ]; then
        echo "${MAIN_REPO_URL}" | ${ELEVATE} tee "${ETC_DIR}/01-main.repo" > /dev/null
    fi

    for REPO in $(find "${ETC_DIR}" -maxdepth 1 -name "*.repo" ! -name 00-builtin.repo ! -name 99-local.repo -type f -printf "%f\n" | sed "s/.repo$//"); do
        if [ ! -e "${ETC_DIR}/${REPO}.d" ]; then
            ${ELEVATE} mkdir "${ETC_DIR}/${REPO}.d" 2>/dev/null
            ${ELEVATE} chmod 755 "${ETC_DIR}/${REPO}.d" 2>/dev/null
        fi
    done
}

function refresh_supported_cache_lists() {
    if [ -f "${CACHE_DIR}/updating_supported.lock" ]; then
        return 0
    else
        ${ELEVATE} touch "${CACHE_DIR}/updating_supported.lock"
        ${ELEVATE} rm -f "${CACHE_DIR}/supported.list" "${CACHE_DIR}/supported_apps.list"
        fancy_message info "Updating cache of supported apps in the background"
        list_debs | grep -v -e '\[+\]' | ${ELEVATE} tee "${CACHE_DIR}/supported.list.tmp" >/dev/null
        # # belt and braces no longer needed
        #${ELEVATE} sed -i '/[+]/d' ${CACHE_DIR}/supported.list.tmp
        cut -d" " -f 1 "${CACHE_DIR}/supported.list.tmp" |sort -u | ${ELEVATE} tee "${CACHE_DIR}/supported_apps.list.tmp" >/dev/null
        ${ELEVATE} mv "${CACHE_DIR}/supported.list.tmp" "${CACHE_DIR}/supported.list"
        ${ELEVATE} mv "${CACHE_DIR}/supported_apps.list.tmp" "${CACHE_DIR}/supported_apps.list"
        ${ELEVATE} rm  "${CACHE_DIR}/updating_supported.lock"
    fi
}

function update_repos() {
    local REPO_URL=""
    # preserve current behaviour for now but allow modification via env
    local CURL_VERBOSITY="-q --show-progress --progress=bar:force:noscroll "
    local UPD_WGET_VERBOSITY=${WGET_VERBOSITY}

    if [[ "$*" == *"--quiet"* ]]  ; then
         CURL_VERBOSITY="-Ss"
         UPD_WGET_VERBOSITY="-q"
         export UPD_WGET_VERBOSITY CURL_VERBOSITY
    fi


    for REPO in $(find "${ETC_DIR}" -maxdepth 1 -name "*.repo" ! -name 00-builtin.repo ! -name 99-local.repo -type f -printf "%f\n" | sed "s/.repo$//"); do
        export REPO ETC_DIR ELEVATE
        fancy_message info "Updating ${ETC_DIR}/${REPO}"
        REPO_URL="$(head -n 1 "${ETC_DIR}/${REPO}.repo")"
        ${ELEVATE} wget ${UPD_WGET_VERBOSITY} ${WGET_TIMEOUT} "${REPO_URL}/manifest" -O "${ETC_DIR}/${REPO}.repo"

        # ${ELEVATE} rm "${ETC_DIR}/${REPO}.d/* # we currently leave old litter : either <- this or maybe rm older ones
        # although so long as manifest is good we are OK
        # Faster by some margin if we are hitting github
        # Otherwise revert to old-style for a bespoke hosted repo

        pushd ${ETC_DIR}/${REPO}.d >/dev/null

        awk -F/ '/github/  {print "# fetching github repo";
                            print "GITREPO="$4"/"$5;\
                            print "BRANCH="$6;\
                            print "curl ${CURL_VERBOSITY} -L https://api.github.com/repos/${GITREPO}/tarball/${BRANCH} | ${ELEVATE} tar zx --wildcards \"*/${REPO}*/packages/*\"   --strip-components=3"}
                ! /github/ {print "# fetching non-github repo";
                            print "tail -n +2 \"${ETC_DIR}/${REPO}.repo\" | sed \"s/^#//\" | ${ELEVATE} sort -u -o \"${ETC_DIR}/${REPO}.repo.tmp\"";\
                            print "${ELEVATE} wget ${UPD_WGET_VERBOSITY} ${WGET_TIMEOUT} -N -B \"${REPO_URL}/packages/\" -i \"${ETC_DIR}/${REPO}.repo.tmp\" -P \"${ETC_DIR}/${REPO}.d\"";
                            print "${ELEVATE} rm \"${ETC_DIR}/${REPO}.repo.tmp\""
                } '\
                <<<${REPO_URL} | bash -

        popd >/dev/null
    done
    refresh_supported_cache_lists &
}

function list_repo_apps() {
    if [ -d "${ETC_DIR}" ]; then
        for REPO in $(find "${ETC_DIR}" -maxdepth 1 -name "*.repo" ! -name 00-builtin.repo ! -name 99-local.repo -type f -printf "%f\n" | sed "s/.repo$//" | sort -r); do
            for APP in $(tail -n +2 "${ETC_DIR}/${REPO}.repo" | grep -v "^#" | sort -u); do
                echo "${REPO}/${APP}"
            done
        done
    fi
}

function list_deprecated_apps() {
    if [ -d "${ETC_DIR}" ]; then
        for REPO in $(find "${ETC_DIR}" -maxdepth 1 -name "*.repo" ! -name 00-builtin.repo ! -name 99-local.repo -type f -printf "%f\n" | sed "s/.repo$//" | sort -r); do
            for APP in $(tail -n +2 "${ETC_DIR}/${REPO}.repo" | grep "^#" | sed "s/^#//" | sort -u); do
                echo "${REPO}/${APP}"
            done
        done
    fi
}

function list_local_apps() {
    if [ -d "${ETC_DIR}/99-local.d" ]; then
        for APP in $(find "${ETC_DIR}/99-local.d" -maxdepth 1 -type f -printf "%f\n"); do
            echo "99-local/${APP}"
        done
    fi
}

function print_etc_overrides() {
    if [ ${#LOCAL_APPS[@]} -gt 0 ] || [ ${#APP_CONFLICTS[@]} -gt 0 ]; then
        local DEB_GET_SCRIPT_FILE="${0}"
        local NUM_OLDER_CONFLICTS=0
        for APP in "${APP_CONFLICTS[@]}"; do
            local FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
            fancy_message warn "Conflict detected, duplicate declaration of package ${APP}, using declaration from $(echo "${FULL_APP}" | cut -d / -f 1)"

            if [[ " ${LOCAL_APPS[*]} " =~ " ${FULL_APP} " ]] && [ "${DEB_GET_SCRIPT_FILE}" -nt "${ETC_DIR}/99-local.d/${APP}" ]; then
                ((NUM_OLDER_CONFLICTS++))
            fi
        done

        if [ "${NUM_OLDER_CONFLICTS}" -gt 0 ]; then
            fancy_message recommend "Duplicate entr(ies) already merged upstream (if no longer needed), must be manually removed from your ${ETC_DIR}/99-local.d folder."
        fi

        for FULL_APP in "${LOCAL_APPS[@]}"; do
            fancy_message info "Including local package $(echo "${FULL_APP}" | cut -d / -f 2)"
        done

        if [ ${#LOCAL_APPS[@]} -gt 0 ]; then
            fancy_message recommend "Please consider contributing back new entries, an issue (or raise a PR) directly at https://github.com/wimpysworld/deb-get/pulls"
        fi
    fi
}

function print_deprecated() {
    for APP in "${DEPRECATED_INSTALLED[@]}"; do
        fancy_message warn "Deprecated package ${APP} detected. It will no longer receive updates, and keeping it installed is considered unsafe."
        fancy_message recommend "Please remove it with: deb-get purge ${APP}"
    done
}

function fix_old_apps() {
    local OLD_METHOD=""
    local OLD_APT_LIST_NAME=""
    local OLD_PPA=""
    case "${APP}" in
        1password)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="1password"
        ;;
        anydesk)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="anydesk-stable"
        ;;
        appimagelauncher)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:appimagelauncher-team/stable"
        ;;
        atom)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="atom"
        ;;
        audio-recorder)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:audio-recorder/ppa"
        ;;
        azure-cli)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="azure-cli"
        ;;
        blanket)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:apandada1/blanket"
        ;;
        brave-browser)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="brave-browser-release"
        ;;
        cawbird)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="home:IBBoard:cawbird"
        ;;
        chronograf)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        code)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="vscode"
        ;;
        copyq)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:hluk/copyq"
        ;;
        cryptomator)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:sebastian-stenzel/cryptomator"
        ;;
        docker-ce)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="docker"
        ;;
        enpass)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="enpass"
        ;;
        firefox-esr)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:mozillateam/ppa"
        ;;
        foliate)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:apandada1/foliate"
        ;;
        fsearch)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:christian-boxdoerfer/fsearch-stable"
        ;;
        google-chrome-stable)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="google-chrome"
        ;;
        google-earth-pro-stable)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="google-earth-pro"
        ;;
        gpu-viewer)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:arunsivaraman/gpuviewer"
        ;;
        influxdb)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        influxdb2)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        influxdb2-cli)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        insync)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="insync"
        ;;
        jellyfin)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="jellyfin"
        ;;
        kapacitor)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        kdiskmark)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:jonmagon/kdiskmark"
        ;;
        keepassxc)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:phoerious/keepassxc"
        ;;
        keybase)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="keybase"
        ;;
        kopia-ui)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="kopia"
        ;;
        lutris)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:lutris-team/lutris"
        ;;
        microsoft-edge-stable)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="microsoft-edge"
        ;;
        neo4j)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="neo4j"
        ;;
        nextcloud-desktop)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:nextcloud-devs/client"
        ;;
        nomad)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="nomad"
        ;;
        obs-studio)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:flexiondotorg/obs-fully-loaded"
        ;;
        openrazer-meta)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:openrazer/stable"
        ;;
        opera-stable)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="opera-stable"
        ;;
        papirus-icon-theme)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:papirus/papirus"
        ;;
        plexmediaserver)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="plexmediaserver"
        ;;
        polychromatic)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:polychromatic/stable"
        ;;
        protonvpn)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="protonvpn-stable"
        ;;
        qownnotes)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:pbek/qownnotes"
        ;;
        quickemu)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:flexiondotorg/quickemu"
        ;;
        quickgui)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:yannick-mauray/quickgui"
        ;;
        resilio-sync)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="resilio-sync"
        ;;
        retroarch)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:libretro/stable"
        ;;
        signal-desktop)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="signal-xenial.list"
        ;;
        skypeforlinux)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="skype-stable"
        ;;
        slack-desktop)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="slack"
        ;;
        softmaker-office-2021)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="softmaker"
        ;;
        strawberry)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:jonaski/strawberry"
        ;;
        sublime-merge)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="sublime-text"
        ;;
        sublime-text)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="sublime-text"
        ;;
        syncthing)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="syncthing"
        ;;
        teams)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="teams"
        ;;
        telegraf)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="influxdata"
        ;;
        terraform)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="terraform"
        ;;
        texworks)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:texworks/stable"
        ;;
        typora)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="typora"
        ;;
        ubuntu-make)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:lyzardking/ubuntu-make"
        ;;
        ulauncher)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:agornostal/ulauncher"
        ;;
        virtualbox-6.1)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="virtualbox-6.1"
        ;;
        vivaldi-stable)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="vivaldi"
        ;;
        wavebox)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="wavebox-stable"
        ;;
        weechat)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="weechat"
        ;;
        wire-desktop)
            OLD_METHOD="apt"
            OLD_APT_LIST_NAME="wire-desktop"
        ;;
        xemu)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:mborgerson/xemu"
        ;;
        yq)
            OLD_METHOD="ppa"
            OLD_PPA="ppa:rmescandon/yq"
        ;;
    esac
    if [ -n "${OLD_METHOD}" ]; then
        if [ "${OLD_METHOD}" = apt ]; then
            remove_old_apt_repo "${OLD_APT_LIST_NAME}"
        else # ppa
            remove_old_ppa_repo "${OLD_PPA}"
        fi
    fi
    if [ "${METHOD}" = apt ]; then
        add_apt_repo
    elif [ "${METHOD}" = ppa ]; then
        ppa_to_apt
        add_apt_repo
    fi
    add_installed

    if [ "${DEFVER}" != 1 ]; then
        fancy_message warn "${APP} must be manually reinstalled with \"deb-get reinstall ${APP}\", otherwise it will not be updated properly"
    fi
}

function fix_installed() {
    local line="$(grep -m 1 "^${APP} " "${ETC_DIR}/installed")"
    local OLD_DEFVER="$(echo "${line}" | cut -d " " -f 2)"
    local OLD_METHOD="$(echo "${line}" | cut -d " " -f 3)"
    if [ "${DEFVER}" != "${OLD_DEFVER}" ]; then
        remove_installed "${APP}"
        if [[ " apt ppa " =~ " ${OLD_METHOD} " ]]; then
            remove_repo --remove-repo
        fi
        if [ "${METHOD}" = apt ]; then
            add_apt_repo
        elif [ "${METHOD}" = ppa ]; then
            ppa_to_apt
            add_apt_repo
        fi
        add_installed
        fancy_message warn "${APP} must be manually reinstalled with \"deb-get reinstall ${APP}\", otherwise it will not be updated properly"
    fi
}

function remove_old_apt_repo() {
    fancy_message info "Removing /etc/apt/trusted.gpg.d/${1}.asc"
    ${ELEVATE} rm -f "/etc/apt/trusted.gpg.d/${1}.asc"
    fancy_message info "Removing /etc/apt/sources.list.d/${1}.list"
    ${ELEVATE} rm -f "/etc/apt/sources.list.d/${1}.list"
}

function remove_old_ppa_repo() {
    local -r PPA_ADDRESS="$(echo "${1}" | cut -d : -f 2)"
    local -r PPA_PERSON="$(echo "${PPA_ADDRESS}" | cut -d / -f 1)"
    local -r PPA_ARCHIVE="$(echo "${PPA_ADDRESS}" | cut -d / -f 2)"
    local -r APT_LIST_NAME="${PPA_PERSON}-ubuntu-${PPA_ARCHIVE}"
    fancy_message info "Removing /etc/apt/trusted.gpg.d/${APT_LIST_NAME}.gpg"
    ${ELEVATE} rm -f "/etc/apt/trusted.gpg.d/${APT_LIST_NAME}.gpg"
    ${ELEVATE} rm -f "/etc/apt/trusted.gpg.d/${APT_LIST_NAME}.gpg~"
    fancy_message info "Removing /etc/apt/sources.list.d/${APT_LIST_NAME}-${UPSTREAM_CODENAME}.list"
    ${ELEVATE} rm -f "/etc/apt/sources.list.d/${APT_LIST_NAME}-${UPSTREAM_CODENAME}.list"
}

function remove_repo() {
    local count=""
    if [ -e "${ETC_DIR}/aptrepos" ]; then
        count="$(grep -m 1 "^${APT_LIST_NAME} " "${ETC_DIR}/aptrepos" | cut -d " " -f 2)"
    fi
    if [ -z "${count}" ]; then
        count=0
    fi
    if [ "${count}" -gt 0 ]; then
        ((count--))
        ${ELEVATE} sed -i -E "/^${APT_LIST_NAME} [0-9]+/d" "${ETC_DIR}/aptrepos"
        echo "${APT_LIST_NAME} ${count}" | ${ELEVATE} tee -a "${ETC_DIR}/aptrepos" > /dev/null
    fi
    if [ "${1}" == --remove-repo ]; then
        if [ "${count}" -eq 0 ]; then
            if [ "${2}" != --quiet ]; then
                fancy_message info "Removing /usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg"
            fi
            ${ELEVATE} rm -f "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg"
            if [ "${2}" != --quiet ]; then
                fancy_message info "Removing /etc/apt/sources.list.d/${APT_LIST_NAME}.list"
            fi
            ${ELEVATE} rm -f "/etc/apt/sources.list.d/${APT_LIST_NAME}.list"
            if [ -e "${ETC_DIR}/aptrepos" ]; then
                ${ELEVATE} sed -i -E "/^${APT_LIST_NAME} [0-9]+/d" "${ETC_DIR}/aptrepos"
            fi
        elif [ "${2}" != --quiet ]; then
            fancy_message warn "/etc/apt/sources.list.d/${APT_LIST_NAME}.list was not removed because other packages depend on it."
        fi
    fi
}

function add_apt_repo() {
    local count=""
    if [ -e "${ETC_DIR}/aptrepos" ]; then
        count="$(grep -m 1 "^${APT_LIST_NAME} " "${ETC_DIR}/aptrepos" | cut -d " " -f 2)"
    fi
    if [ -z "${count}" ]; then
        count=0
    fi
    if [ "${count}" -eq 0 ] && [ -e "/etc/apt/sources.list.d/${APT_LIST_NAME}.list" ]; then
        ((count++))
    fi
    ((count++))
    if [ -e "${ETC_DIR}/aptrepos" ]; then
        ${ELEVATE} sed -i -E "/^${APT_LIST_NAME} [0-9]+/d" "${ETC_DIR}/aptrepos"
    fi
    echo "${APT_LIST_NAME} ${count}" | ${ELEVATE} tee -a "${ETC_DIR}/aptrepos" > /dev/null
    if [ ! -d /usr/share/keyrings ]; then
        ${ELEVATE} mkdir -p /usr/share/keyrings 2>/dev/null
    fi
    if [ ! -e "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg" ]; then
        if [ -n "${ASC_KEY_URL}" ]; then
            ${ELEVATE} wget ${WGET_VERBOSITY} ${WGET_TIMEOUT} "${ASC_KEY_URL}" -O "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring"
            ${ELEVATE} gpg --yes --dearmor "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring"
            ${ELEVATE} rm "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring"
        elif [ -n "${GPG_KEY_ID}" ]; then
            ${ELEVATE} gpg --no-default-keyring --keyring /usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg --keyserver keyserver.ubuntu.com --recv ${GPG_KEY_ID}
        else #GPG_KEY_URL
            ${ELEVATE} wget ${WGET_VERBOSITY} ${WGET_TIMEOUT} "${GPG_KEY_URL}" -O "/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg"
        fi
    fi

    local APT_LIST_LINE="deb [signed-by=/usr/share/keyrings/${APT_LIST_NAME}-archive-keyring.gpg"

    if [ -n "${APT_REPO_OPTIONS}" ]; then
        APT_LIST_LINE="${APT_LIST_LINE} ${APT_REPO_OPTIONS}"
    fi

    APT_LIST_LINE="${APT_LIST_LINE}] ${APT_REPO_URL}"
    echo "${APT_LIST_LINE}" | ${ELEVATE} tee "/etc/apt/sources.list.d/${APT_LIST_NAME}.list" > /dev/null
}

function ppa_to_apt() {
    local -r PPA_ADDRESS="$(echo "${PPA}" | cut -d : -f 2)"
    local -r PPA_PERSON="$(echo "${PPA_ADDRESS}" | cut -d / -f 1)"
    local -r PPA_ARCHIVE="$(echo "${PPA_ADDRESS}" | cut -d / -f 2)"
    export APT_REPO_URL="https://ppa.launchpadcontent.net/${PPA_ADDRESS}/ubuntu/ ${UPSTREAM_CODENAME} main"
    export ASC_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$(curl -s "https://api.launchpad.net/devel/~${PPA_PERSON}/+archive/ubuntu/${PPA_ARCHIVE}" | grep -o -E "\"signing_key_fingerprint\": \"[0-9A-F]+\"" | cut -d \" -f 4)"
    export APT_LIST_NAME="${PPA_PERSON}-ubuntu-${PPA_ARCHIVE}-${UPSTREAM_CODENAME}"
}

function maint_supported_cache() {
    # called by install and re-install when we've installed
    # so we should be supported

    if [ -f ${CACHE_DIR}/supported.list ]; then
        case "${ACTION}" in
            remove|purge)
                ${ELEVATE} sed -i "/^${APP} /d" ${CACHE_DIR}/supported.list
                cat ${CACHE_DIR}/supported.list - <<<"${APP}" | ${ELEVATE} sort -t " " -k 1 -u -o ${CACHE_DIR}/supported.list
                ;;
            reinstall|install)
                local PAD='                              '
                local cache_line=$(printf "%s %s [ installed ]\n" "${APP}" "${PAD:${#APP}}")
                # # First remove the bare entry
                ${ELEVATE} sed -i -e '/^${APP}$/d' ${CACHE_DIR}/supported.list
                # Replace it with a flagged one
                cat ${CACHE_DIR}/supported.list - <<<"${cache_line}" | ${ELEVATE} sort -t " " -k 1 -u -o ${CACHE_DIR}/supported.list
                # should be there but safest to be sure
                grep -q -w ${APP}$ ${CACHE_DIR}/supported_apps.list || \
                cat ${CACHE_DIR}/supported_apps.list - <<<"${APP}" | ${ELEVATE} sort -t " " -k 1 -u -o ${CACHE_DIR}/supported_apps.list
                ;;
        esac
    fi
}

function add_installed() {
    local line="${APP} ${DEFVER} ${METHOD}"
    cat "${ETC_DIR}/installed" - <<< "${line}" | ${ELEVATE} sort -t " " -k 1 -u -o "${ETC_DIR}/installed"
}

function remove_installed() {
    ${ELEVATE} sed -i "/^${1} /d" "${ETC_DIR}/installed"
}

function deb_deb-get() {
    DEFVER=1
    ARCHS_SUPPORTED="amd64 arm64 armhf i386"
    get_github_releases "wimpysworld/deb-get"
    if [ "${ACTION}" != "prettylist" ]; then
        URL="$(grep "browser_download_url.*\.deb\"" "${CACHE_FILE}" | head -n1 | cut -d'"' -f4)"
        VERSION_PUBLISHED="$(echo "${URL}" | cut -d'_' -f2)"
    fi
    PRETTY_NAME="deb-get"
    WEBSITE="https://github.com/wimpysworld/deb-get"
    SUMMARY="'apt-get' functionality for .debs published in 3rd party repositories or via direct download package."
}

#### MAIN ####

WGET_VERBOSITY=${WGET_VERBOSITY:="-q"}
WGET_TIMEOUT=${WGET_TIMEOUT:="--timeout 5"}
export WGET_TIMEOUT WGET_VERBOSITY
export CACHE_DIR="/var/cache/deb-get"
readonly ETC_DIR="/etc/deb-get"
readonly MAIN_REPO_URL="https://raw.githubusercontent.com/wimpysworld/deb-get/main/01-main"

if ((BASH_VERSINFO[0] < 4)); then
    fancy_message fatal "Sorry, you need bash 4.0 or newer to run $(basename "${0}")."
fi

if ! command -v lsb_release 1>/dev/null; then
  fancy_message fatal "lsb_release not detected. Quitting."
fi

export HOST_CPU="$(uname -m)"
case ${HOST_CPU} in
  aarch64|armv7l|x86_64) export HOST_ARCH="$(dpkg --print-architecture)";;
  *) fancy_message fatal "${HOST_CPU} is not supported. Quitting.";;
esac

readonly USER_AGENT="Mozilla/5.0 (X11; Linux ${HOST_CPU}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"
readonly USER_HOME="${HOME}"

OS_ID=$(lsb_release --id --short)
case "${OS_ID}" in
  Debian) OS_ID_PRETTY="Debian";;
  Linuxmint) OS_ID_PRETTY="Linux Mint";;
  Neon) OS_ID_PRETTY="KDE Neon";;
  Pop) OS_ID_PRETTY="Pop!_OS";;
  Ubuntu) OS_ID_PRETTY="Ubuntu";;
  Zorin) OS_ID_PRETTY="Zorin OS";;
  *)
    OS_ID_PRETTY="${OS_ID}"
    fancy_message warn "${OS_ID} is not supported."
  ;;
esac

OS_CODENAME=$(lsb_release --codename --short)

if [ -e /etc/os-release ]; then
    OS_RELEASE=/etc/os-release
elif [ -e /usr/lib/os-release ]; then
    OS_RELEASE=/usr/lib/os-release
else
    fancy_message fatal "os-release not found. Quitting"
fi

UPSTREAM_ID="$(grep "^ID=" ${OS_RELEASE} | cut -d'=' -f2)"

# Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
if [ "${UPSTREAM_ID}" != ubuntu ] && [ "${UPSTREAM_ID}" != debian ]; then
    UPSTREAM_ID_LIKE="$(grep "^ID_LIKE=" ${OS_RELEASE} | cut -d'=' -f2 | cut -d \" -f 2)"

    if [[ " ${UPSTREAM_ID_LIKE} " =~ " ubuntu " ]]; then
        UPSTREAM_ID=ubuntu
    elif [[ " ${UPSTREAM_ID_LIKE} " =~ " debian " ]]; then
        UPSTREAM_ID=debian
    else
        fancy_message fatal "${OS_ID_PRETTY} ${OS_CODENAME^} is not supported because it is not derived from a supported Debian or Ubuntu release."
    fi
fi

UPSTREAM_CODENAME=$(grep "^UBUNTU_CODENAME=" ${OS_RELEASE} | cut -d'=' -f2)

if [ -z "${UPSTREAM_CODENAME}" ]; then
    UPSTREAM_CODENAME=$(grep "^DEBIAN_CODENAME=" ${OS_RELEASE} | cut -d'=' -f2)
fi

if [ -z "${UPSTREAM_CODENAME}" ]; then
    UPSTREAM_CODENAME=$(grep "^VERSION_CODENAME=" ${OS_RELEASE} | cut -d'=' -f2)
fi

# Debian 12+
if [ -z "${UPSTREAM_CODENAME}" ] && [ -e /etc/debian_version ]; then
    UPSTREAM_CODENAME=$(cut -d / -f 1 /etc/debian_version)
fi

case "${UPSTREAM_CODENAME}" in
    buster)   UPSTREAM_RELEASE="10";;
    bullseye) UPSTREAM_RELEASE="11";;
    bookworm) UPSTREAM_RELEASE="12";;
    trixie)   UPSTREAM_CODENAME="13";;
    sid)      UPSTREAM_RELEASE="unstable";;
    focal)    UPSTREAM_RELEASE="20.04";;
    jammy)    UPSTREAM_RELEASE="22.04";;
    kinetic)  UPSTREAM_RELEASE="22.10";;
    lunar)    UPSTREAM_RELEASE="23.04";;
    mantic)   UPSTREAM_RELEASE="23.10";;
    *) fancy_message fatal "${OS_ID_PRETTY} ${OS_CODENAME^} is not supported because it is not derived from a supported Debian or Ubuntu release.";;
esac

if [ -n "${1}" ]; then
    ACTION="${1,,}"
    shift
else
    fancy_message error "You must specify an action."
    usage >&2
    exit 1
fi

case "${ACTION}" in
    update|upgrade|show|reinstall|install|remove|purge|search|list|pretty_list|prettylist|csv_list|csvlist|csv|fix-installed)
    APPS="$(list_local_apps)"
    APPS="${APPS}
$(list_repo_apps)"
    APPS="${APPS}
$(declare -F | grep deb_ | sed 's|declare -f deb_|00-builtin/|g')"
    readonly APP_CONFLICTS=($(echo "${APPS}" | cut -d / -f 2 | sort | uniq --repeated))
    APPS="$(echo "${APPS}" | sort -t / -k 2 -u)"
    readonly LOCAL_APPS=($(echo "${APPS}" | grep "^99-local/"))
    if [ -e "${ETC_DIR}/installed" ]; then
        INSTALLED_APPS=($(cut -d " " -f 1 "${ETC_DIR}/installed"))
    else
        INSTALLED_APPS=()
    fi
    APPS=(${APPS})
    ;;
esac

case ${ACTION} in
    install|reinstall|remove|purge|show)
        if [ -z "${1}" ]; then
            fancy_message error "You must specify an app:\n"
            ACTION="list"
            list_debs "" --raw >&2
            exit 1
        fi
        print_etc_overrides
        DEPRECATED_APPS="$(list_deprecated_apps | sort -t / -k 2 -u)"
        if [ -n "${DEPRECATED_APPS}" ]; then
            readonly DEPRECATED_INSTALLED=($(dpkg-query -f '${db:Status-abbrev}:${Package}\n' -W $(echo "${DEPRECATED_APPS}" | cut -d / -f 2 | tr "\n" " ") 2> /dev/null | grep "^ii " | cut -d : -f 2))
        else
            readonly DEPRECATED_INSTALLED=()
        fi
        DEPRECATED_APPS=(${DEPRECATED_APPS})
        print_deprecated;;
esac

export ELEVATE=""

case "${ACTION}" in
    cache)
        ls -lh "${CACHE_DIR}/";;
    clean)
        elevate_privs
        ${ELEVATE} rm -fv "${CACHE_DIR}"/*.deb
        ${ELEVATE} rm -fv "${CACHE_DIR}"/*.json
        ${ELEVATE} rm -fv "${CACHE_DIR}"/*.html
        ${ELEVATE} rm -fv "${CACHE_DIR}"/*.txt
        ;;
    show)
        for APP in "${@,,}"; do
            FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
            if [ -z "${FULL_APP}" ]; then
                fancy_message error "${APP} is not a supported application."
                ACTION="list"
                list_debs "" --raw >&2
                exit 1
            fi
            validate_deb "${FULL_APP}"
            info_deb
        done;;
    install|reinstall)
        elevate_privs
        create_cache_dir
        create_etc_dir
        for APP in "${@,,}"; do
            FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
            if [ -z "${FULL_APP}" ]; then
                fancy_message error "${APP} is not a supported application."
                ACTION="list"
                list_debs "" --raw >&2
                exit 1
            fi
            validate_deb "${FULL_APP}"
            if [[ "${ARCHS_SUPPORTED}" != *"${HOST_ARCH}"* ]]; then
                fancy_message fatal "${APP} is not supported on ${HOST_ARCH}."
            fi

            if [ -n "${CODENAMES_SUPPORTED}" ] && ! [[ "${CODENAMES_SUPPORTED[*]}" =~ "${UPSTREAM_CODENAME}" ]]; then
                fancy_message fatal "${APP} is not supported on ${OS_ID_PRETTY} ${UPSTREAM_CODENAME^}."
            fi

            if [ "${METHOD}" == "ppa" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
                fancy_message fatal "${APP} cannot be installed as PPAs are not supported on distros that are not derived from Ubuntu."
            fi

            case ${METHOD} in
                direct|github|website) install_deb "${URL}";;
                apt) install_apt;;
                ppa) install_ppa;;
            esac
        done;;
    list)
        list_opt_1=""
        list_opt_2=""
        while [ -n "${1}" ]; do
            if [ "${1}" == --include-unsupported ]; then
                list_opt_1=--include-unsupported
            elif [[ " --raw --installed --not-installed --only-unsupported " =~ " ${1} " ]]; then
                list_opt_2="${1}"
            else
                fancy_message fatal "Unknown option supplied: ${1}"
            fi
            shift
        done
        list_debs "${list_opt_1}" "${list_opt_2}";;
    pretty_list|prettylist)
        ACTION="prettylist"
        prettylist_debs "${1}";;
    csv_list|csvlist|csv)
        ACTION="prettylist"
        csvlist_debs "${1}";;
    purge)
        elevate_privs
        opt_remove_repo=""
        if [ "${1}" == --remove-repo ]; then
            opt_remove_repo=--remove-repo
            shift
        fi
        for APP in "${@,,}"; do
            FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
            if [ -z "${FULL_APP}" ]; then
                FULL_APP="$(IFS=$'\n'; echo "${DEPRECATED_APPS[*]}" | grep -m 1 "/${APP}$")"
            fi
            if [ -z "${FULL_APP}" ]; then
                fancy_message error "${APP} is not a supported application."
                ACTION="list"
                list_debs "" --raw >&2
                exit 1
            fi
            validate_deb "${FULL_APP}"
            remove_deb "${APP}" purge "${opt_remove_repo}"
        done;;
    remove)
        elevate_privs
        opt_remove_repo=""
        if [ "${1}" == --remove-repo ]; then
            opt_remove_repo=--remove-repo
            shift
        fi
        for APP in "${@,,}"; do
            FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
            if [ -z "${FULL_APP}" ]; then
                FULL_APP="$(IFS=$'\n'; echo "${DEPRECATED_APPS[*]}" | grep -m 1 "/${APP}$")"
            fi
            if [ -z "${FULL_APP}" ]; then
                fancy_message error "${APP} is not a supported application."
                ACTION="list"
                list_debs "" --raw >&2
                exit 1
            fi
            validate_deb "${FULL_APP}"
            remove_deb "${APP}" "" "${opt_remove_repo}"
        done;;
    search)
        if [ "${1}" == --include-unsupported ]; then
            if [ -z "${2}" ]; then
                fancy_message error "You must specify a pattern."
                usage >&2
                exit 1
            fi
            list_debs --include-unsupported --raw | grep "${2}"
        else
            list_debs "" --raw | grep "${1}"
        fi;;
    update)
        if [ -n "${1}" ] && [ "${1}" != --repos-only ] && [ "${1}" != --quiet ]; then
            fancy_message fatal "Unknown option supplied: ${1}"
        elif [ -n "${2}" ] && [ "${2}" != --repos-only ] && [ "${2}" != --quiet ]; then
                fancy_message fatal "Unknown option supplied: ${2}"
        fi
        if [ -n "${3}" ] ; then
                    fancy_message error "Ignoring extra options from : ${3}"
        fi
        elevate_privs
        create_cache_dir
        create_etc_dir
        init_repos
        update_repos "$@"
        #if [ "${1}" != --repos-only ]; then
        if [[ "$*" != *"--repos-only"* ]] ; then
            APPS="$(list_local_apps)"
            APPS="${APPS}
$(list_repo_apps)"
            APPS="${APPS}
$(declare -F | grep deb_ | sed 's|declare -f deb_|00-builtin/|g')"
            APPS=($(echo "${APPS}" | sort -t / -k 2 -u))
            for APP in "${INSTALLED_APPS[@]}"; do
                FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
                if [ -n "${FULL_APP}" ]; then
                    validate_deb "${FULL_APP}"
                    fix_installed
                else
                    remove_installed "${APP}"
                fi
            done
            INSTALLED_APPS=($(cut -d " " -f 1 "${ETC_DIR}/installed"))
            update_debs
        fi;;
    upgrade)
        elevate_privs
        create_cache_dir
        upgrade_debs;;
    fix-installed)
        if [ -n "${1}" ] && [ "${1}" != --old-apps ]; then
            fancy_message fatal "Unknown option supplied: ${1}"
        fi
        elevate_privs
        if [ "${1}" = --old-apps ]; then
            for APP in $(dpkg-query -f '${db:Status-abbrev}:${Package}\n' -W $(IFS=$'\n'; echo "${APPS[*]}" | cut -d / -f 2 | tr "\n" " ") 2> /dev/null | grep "^ii " | cut -d : -f 2); do
                validate_deb "$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
                fix_old_apps
            done
        else
            for APP in "${INSTALLED_APPS[@]}"; do
                FULL_APP="$(IFS=$'\n'; echo "${APPS[*]}" | grep -m 1 "/${APP}$")"
                if [ -n "${FULL_APP}" ]; then
                    validate_deb "${FULL_APP}"
                    fix_installed
                else
                    remove_installed "${APP}"
                fi
            done
        fi;;
    version) echo "${VERSION}";;
    help) usage;;
    *) fancy_message fatal "Unknown action supplied: ${ACTION}";;
esac

if [[ ${PACKAGE_INSTALLATION_COUNT} -lt ${PACKAGE_INSTALLATION_TRIES} ]]; then
    exit 1
fi
