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
            -d | --dir)
                # Remove slash
                _dir="${1%/}"
                shift
                ;;
            -e | --expires)
                _expires=${1}
                shift
                ;;
            -g | --target)
                _target=${1}
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
     -d|--dir                         Cache directory path
     -e|--expires                     Curl expiry age (default 60s).
     -g|--target                      Target file
     -h|--help                        Displays this help
     -t|--token                       Authorization token to use
     -v|--verbose                     Displays verbose output

Overrides:
    SHELL_EXPORTER_CACHE_EXPIRES      Curl expiry age (default 60s).
    SHELL_EXPORTER_CACHE_DIR          Cache folder
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

function my_curl() {
    local _response

    _response=$(curl -w "%{http_code}" -X ${_method} -sI --retry 10 --retry-delay 5 -H "Authorization: Bearer ${_token}" -H "api-key: ${_apikey}" ${_url};)    

    echo "${_response}"
}

function cached_curl() {
    local _progr
    local _hash
    local _apikey
    local _url
    local _curl_response
    local _curl_send
    
    _apikey=$1
    _url=$2

    _prog="$(basename $0)"
    _hash=$(echo "${_apikey}${_url}" | md5sum | cut -f1 -d ' ')
    _cacheFile="${_dir}/${_hash}"
    verbose_print "Cache file: ${_cacheFile}"
    _tempFile=$(mktemp)
    _curl_send=false
    if [[ -f ${_cacheFile} ]]; then
        if [[ $(expr $(date +%s) - $(date -r "$_cacheFile" +%s)) -ge $_expires ]]; then
            verbose_print "Cache expired, requesting to ${_url}"
            # make it retry ten times and sleep five seconds before retrying:
            # print the http code: -w "%{http_code}"
            _curl_response="$(my_curl)"
            _curl_send=true
        fi
    else
        verbose_print "No cache found, requesting to ${_url}"
        mkdir -p ${_dir}
        #  make it retry ten times and sleep five seconds before retrying:--retry 10 --retry-delay 5
        # print the http code: -w "%{http_code}"
        _curl_response="$(my_curl)"
        _curl_send=true
    fi
    # verbose_print "cUrl: ${_curl_response}"
    _curl_http_code=$(tail -n1 <<< "$_curl_response")  # get the last line
    # verbose_print "cUrl http code: ${_curl_http_code}"
    if [[ "${_curl_http_code}" -eq 200 ]] ; then
        verbose_print "caching into ${_cacheFile}"
        echo "$_curl_response" > ${_cacheFile}
    else
        if [[ "$_curl_send" = true ]]; then
            # There is a problem with the request, invalidate the cache
            verbose_print "(${_curl_http_code}) Invalidating cache ${_cacheFile}"
            rm -f ${_cacheFile}
        fi
    fi
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    local key
    local value
    local _url
    local _apikey
    local _apiname

    parse_params "$@"
    override_params
    envsubst < ${_target} > /tmp/target.txt
    # Each line <apiname>,<apikey>,<url>
    while read p; do
        case $p in
            ''|\#*) continue ;;         # skip blank lines and lines starting with #
        esac
        _apiname=$(echo $p | cut -f1 -d ',');
        _apikey=$(echo $p | cut -f2 -d ',');
        _url=$(echo $p | cut -f3 -d ',');
        cached_curl ${_apikey} ${_url}
        if [[ -f ${_cacheFile} ]]; then
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
                    HTTP*) read _proto _status _msg <<< "$key{$value:+:$value}"
                        ;;
                esac
            done < ${_cacheFile}
            echo "${_apiname}:${_apikey}:x-ratelimit-remaining-hour:${_xRatelimitRemainingHour##[[:space:]]}";
            echo "${_apiname}:${_apikey}:x-ratelimit-remaining-second:${_xRatelimitRemainingSecond##[[:space:]]}";
            echo "${_apiname}:${_apikey}:x-ratelimit-limit-hour:${_xRatelimitHour##[[:space:]]}";
            echo "${_apiname}:${_apikey}:x-ratelimit-limit-second:${_xRatelimitSecond##[[:space:]]}";
        fi;
    done < /tmp/target.txt
    rm /tmp/target.txt
}

main "$@"
