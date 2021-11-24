#!/usr/bin/env bash

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    local _bin

    _bin="$(basename $0)"

    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -a | --apikey)
                _apikey=${1}
                shift
                ;;
            -d | --dir)
                # Remove slash 
                _dir="${1%/}"
                shift
                ;;
            -e | --expires)
                _expires=${1}
                shift
                ;;    
            -h | --help)
                script_usage
                exit 0
                ;;
            -t | --token)
                _token=${1}
                shift
                ;;
            -u | --url)
                _url=${1}
                shift
                ;;
            -v | --verbose)
                _verbose=true
                shift
                ;;
            *)
                echo "Invalid parameter was provided: $param"
                exit 1
                ;;
        esac
    done
}

function override_params() {

    _method="GET"
    # Default curl cache time in seconds
    _expires=${SHELL_EXPORTER_CACHE_EXPIRES:-60}  
    _dir=${SHELL_EXPORTER_CACHE_DIR:-"./.cache"}
    if [[ -z ${_token} ]]; then
        _token=$([[ -f ${_token} ]] && cat /token/token.txt)
    fi
    if [ ! -z ${SHELL_EXPORTER_APIKEY+x} ]; then
        _apikey=${SHELL_EXPORTER_APIKEY}
    fi
    if [ ! -z ${SHELL_EXPORTER_TOKEN+x} ]; then
        _token=${SHELL_EXPORTER_TOKEN}
    fi
}

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage: bctf_metrics [args]

Arguments:
     -a|--apikey                      Apikey used to contact bctf servers
     -d|--dir                         Cache directory path
     -e|--expires                     Curl expiry age (default 60s).
     -h|--help                        Displays this help
     -u|--url                         Url to check
     -t|--token                       Authorization token to use
     -v|--verbose                     Displays verbose output

Overrides:
    SHELL_EXPORTER_CACHE_EXPIRES      Curl expiry age (default 60s).
    SHELL_EXPORTER_CACHE_DIR          Cache folder
    SHELL_EXPORTER_CACHE_APIKEY       Apikey used to contact bctf servers
    SHELL_EXPORTER_CACHE_TOKEN        Authorization token to use
EOF
}

# DESC: Only pretty_print() the provided string if verbose mode is enabled
# ARGS: $@ (required): Passed through to pretty_print() function
# OUTS: None
function verbose_print() {

    if [[ ! -z ${_verbose} ]]; then
        echo "$1"
    fi
}

function cached_curl() {
    local _progr

    _prog="$(basename $0)"
    _hash=$(echo "${_apikey}${_url}" | md5sum | cut -f1 -d ' ')
    _cacheFile="${_dir}/${_hash}"
    if [[ -f ${_cacheFile} ]]; then
        if [[ $(expr $(date +%s) - $(date -r "$_cacheFile" +%s)) -ge $_expires ]]; then
            verbose_print "Cache expired, requesting to ${_url}"
            curl -X ${_method} -sI -H "Authorization: Bearer ${_token}" -H "api-key: ${_apikey}" ${_url} > $_cacheFile
        fi
    else
        verbose_print "No cache found, requesting to ${_url}"
        mkdir -p ${_dir}
        curl -X ${_method} -sI -H "Authorization: Bearer ${_token}" -H "api-key: ${_apikey}" ${_url} > $_cacheFile
    fi
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    local key
    local value

    parse_params "$@"
    override_params
    cached_curl

    while IFS=':' read key value; do
        # trim whitespace in "value"
        value=${value##+([[:space:]])}; value=${value%%+([[:space:]])}
        case $key in
            x-ratelimit-limit-second) 
                _xRatelimitSecond=${value}
                ;;
            x-ratelimit-limit-hour) 
                _xRatelimitHour=${value}
                ;;
            x-ratelimit-remaining-second) 
                _xRatelimitRemainingSecond=${value}
                ;;
            x-ratelimit-remaining-hour) 
                _xRatelimitRemainingHour=${value}
                ;;
            # HTTP*) read _proto _status _msg <<< "$key{$value:+:$value}"
            #     ;;
        esac        
    done < ${_cacheFile}

    echo "${_apikey}:x-ratelimit-remaining-hour:${_xRatelimitRemainingHour##[[:space:]]}";
    echo "${_apikey}:x-ratelimit-remaining-second:${_xRatelimitRemainingSecond##[[:space:]]}";
    echo "${_apikey}:x-ratelimit-limit-hour:${_xRatelimitHour##[[:space:]]}";
    echo "${_apikey}:x-ratelimit-limit-second:${_xRatelimitSecond##[[:space:]]}";
}

main "$@"
