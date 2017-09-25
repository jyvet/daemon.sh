#!/bin/bash
################################################################################
#                              The Unlicense                                   #
#                            2017 Jean-Yves VET                                #
#                                                                              #
#  This is free and unencumbered software released into the public domain.     #
#                                                                              #
#  Anyone is free to copy, modify, publish, use, compile, sell, or distribute  #
#  this software, either in source code form or as a compiled binary, for any  #
#  purpose, commercial or non-commercial, and by any means.                    #
#                                                                              #
#  In jurisdictions that recognize copyright laws, the author or authors of    #
#  this software dedicate any and all copyright interest in the software to    #
#  the public domain. We make this dedication for the benefit of the public    #
#  at large and to the detriment of our heirs and successors. We intend this   #
#  dedication to be an overt act of relinquishment in perpetuity of all        #
#  present and future rights to this software under copyright law.             #
#                                                                              #
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR  #
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,    #
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL     #
#  THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER    #
#  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN     #
#  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.  #
#                                                                              #
#  For more information, please refer to <http://unlicense.org>                #
#                                                                              #
####----[ FULL USAGE ]------------------------------------------------------####
#% Synopsis:                                                                   #
#+    {{SC_NAME}} [options...]                                                 #
#%                                                                             #
#% Description:                                                                #
#%    Daemonize bash scripts.                                                  #
#%                                                                             #
#% Options:                                                                    #
#%    -d, --daemon                     Daemonize the script.                   #
#%    -h, --help                       Print this help.                        #
#%    -q, --quiet                      Do not print or log anything.           #
#%        --version                    Print script information.               #
#%                                                                             #
####----[ INFORMATION ]-----------------------------------------------------####
#% Implementation:                                                             #
#-    version         0.1                                                      #
#-    url             https://github.com/jyvet/daemon.sh                       #
#-    author          Jean-Yves VET <contact[at]jean-yves.vet>                 #
#-    created         September 25, 2017                                       #
#-    license         The Unlicense                                            #
##################################HEADER_END####################################


####----[ PARAMETERS ]------------------------------------------------------####

    IS_DAEMON='false'               # Do not daemonize this scrit by default
    LOG_FILE='/tmp/daemon.log'      # Where the log file sould be stored
    FREQUENCY=10                    # Frequency (in seconds) of this script


####----[ GLOBAL VARIABLES ]------------------------------------------------####

    readonly SC_HSIZE=$(sed -n '/#HEADER_END#/ { =; q }' ${0}) # Get header size
    readonly SC_DIR=$(dirname $(readlink -f "${BASH_SOURCE[0]}")) # Retrieve
                                         # path where script is located
    readonly SC_NAME=$(basename ${0})    # Retrieve name of the script
    readonly SC_PID=$(echo $$)           # Retrieve PID of the script


####----[ GENERIC FUNCTIONS ]-----------------------------------------------####

    ############################################################################
    # Replace tags with content of variables.                                  #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text.             #
    #      -$3: Start of the tag.                                              #
    #      -$4: End of the tag.                                                #
    # Result: store the resulting text in the variable defined by $2.          #
    tags_replace()
    {
        # Extract arguments
        local in="$1"
        local out="$2"
        local stag="$3"
        local etag="$4"

        # Search list of tags to replace
        local varList=$(echo "$in" | egrep -o "$stag[0-9A-Za-z_-]*$etag" |
                        sort -u | sed -e "s/^$stag//" -e "s/$etag$//")

        local res="$in"

        # Check if there are some tags to replace
        if [[ -n "$varList" ]]; then
            # Generate sed remplacement string
            sedOpts=''
            for var in $varList; do
                eval "value=\${${var}}"
                sedOpts="${sedOpts} -e 's#$stag${var}$etag#${value}#g'"
            done

            res=$(eval "echo -e \"\$in\" | sed $sedOpts")
        fi

        # Store resulting string in the output variable
        eval "$out=\"$res\""
    }

    ############################################################################
    # Remove all tags contained in a text.                                     #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text.             #
    #      -$3: Start of the tag.                                              #
    #      -$4: End of the tag.                                                #
    # Result: store the resulting text in the variable defined by $2.          #
    tags_remove()
    {
        # Extract arguments
        local in="$1"
        local out="$2"
        local stag="$3"
        local etag="$4"

        # Remove tags
        local res="$(echo "$in" | sed -e "s#$stag[A-Za-z0-9_]*$etag##g")"

        # Store resulting string in the output variable
        eval "$out=\"$res\""
    }

    ############################################################################
    # Replace tags in a text with the content of variables.                    #
    # Args:                                                                    #
    #      -$1: Input text.                                                    #
    #      -$2: Output variable where to store the resulting text or output    #
    #           the content. ($2='var_name', $2='stdout' or $2='stderr')       #
    # Result: store or output the resulting text.                              #
    tags_replace_txt()
    {
        # Extract arguments
        local in="$1"
        local out="$2"

        # Replace all tags defined by {{TAG_NAME}}
        tags_replace "$in" "$out" '{{' '}}'

        # Check if the resulting string has to be printed in stderr or stdout
        case "$out" in
            stdout)
                eval "echo -e \"\$$out\""
                ;;
            stderr)
                eval "echo -e \"\$$out\"" 1>&2
                ;;
        esac
    }

    ############################################################################
    # Print warning in stderr.                                                 #
    # Args:                                                                    #
    #      -$1: Message to print.                                              #
    # Result: print warning.                                                   #
    print_warn()
    {
        # Extract argument
        local msg="$1"

        # Print the error message if quiet mode is not activated.
        if [[ "$IS_QUIET" != 'true' ]]; then
            echo "Warning: $msg" 1>&2
        fi
    }

    ############################################################################
    # Print usage.                                                             #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print short usage message.                                       #
    usage()
    {
        printf 'Usage: '
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#+" |
                   sed -e "s/^#+[ ]*//g" -e "s/#$//g")

        tags_replace_txt "$tmp" 'stdout'
    }

    ############################################################################
    # Print information related to development.                                #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print version and contact information.                           #
    info()
    {
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#-" |
                        sed -e "s/^#-//g" -e "s/#$//g" -e "s/\[at\]/@/g")

        tags_replace_txt "$tmp" 'stdout'
    }

    ############################################################################
    # Print full detailled usage.                                              #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print help.                                                      #
    usage_full()
    {
        local tmp=$(head -n${SC_HSIZE:-99} "${0}" | grep -e "^#[%+]" |
                       sed -e "s/^#[%+-]//g" -e "s/#$//g")

        tags_replace_txt "$tmp" 'stdout'

        info
    }

    ############################################################################
    # Check arguments.                                                         #
    # Args:                                                                    #
    #       All arguments provided.                                            #
    # Result: check if arguments are allowed and set global variables.         #
    check_arguments()
    {
        ARGS=$(getopt -o dhqv -l daemon,help,quiet,version -n "$0" -- "$@") ||
        {
            usage; return $EINVAL
        }

        eval set -- "$ARGS"; unset ARGS

        # Parse common arguments (activate modes before doing other actions)
        while true
        do
            case "$1" in
                -h|--help)
                    usage_full; exit 0;;
                --version)
                    info; exit 0;;
                --)
                    ARGS+=" $1"; shift
                    break;;
                *)
                    ARGS+=" $1"; shift;;
            esac
        done

        eval set -- "$ARGS"; unset ARGS

        # Parse application specific arguments
        while true
        do
            case "$1" in
                -d|--daemon)
                    IS_DAEMON='true'
                    shift;;
                -q|--quiet)
                    IS_QUIET='true'
                    shift;;
                --)
                    shift; break;;
                *)
                    ARG="$1"
                    print_error $EINVAL; usage; return $EINVAL;;
            esac
        done
    }

    ############################################################################
    # Daemonize this script if the proper argument was provided. Following URL #
    # URL: http://www.faqs.org/faqs/unix-faq/programmer/faq/ gives some steps  #
    # to create a daemon process. This function implements those steps.        #
    # Args:                                                                    #
    #       All arguments provided.                                            #
    # Result: Daemonize the script.                                            #
    daemonize()
    {
        # Return if the script should not be run as a daemon.
        if [[ "$IS_DAEMON" != 'true' ]]; then
            print_warn "$SC_NAME is not run as a daemon"
            return
        fi

        # Make parent process fork and exit. This returns control to the
        # command line or shell invoking the script. This step is required so
        # that the new process is guaranteed not to be a process group leader.
        # Call `setsid()' to become a process group and session group leader.
        # The new process becomes a child of init (it has no controlling
        # terminal).
        if [[ ! "$1" =~ 'fork#' ]]; then
            setsid ${SC_DIR}/${SC_NAME} '#fork#' "$@" &
            exit $?
        fi

        # Make the child process fork again to ensures that the daemon process
        # is not the session leader. It prevents the daemon from acquiring a
        # tty.
        if [[ "$1" = '#fork#' ]]; then
            shift

            # Get complete control over write permissions (avoid inheritance).
            umask 0

            # Release standard in, out, and error inherited from parent process
            ${SC_DIR}/${SC_NAME} '#refork#' "$@" \
                         </dev/null >/dev/null 2>/dev/null &
            exit 0
        fi

        shift

        # Change directory to root to ensure that the process does not keep
        # any directory in use (otherwise it might prevent and administrator
        # from unmounting a filesystem).
        cd /

        # Establish new open descriptors for stdin, stdout and stderr.
        exec 2>> ${LOG_FILE}
        exec 1>> ${LOG_FILE}
        exec 0<  /dev/null

        print_warn "Daemon started - $(date +'%c')"
    }


####----[ FUNCTIONS ]-------------------------------------------------------####

    ############################################################################
    # Modify this function to periodically launch some work.                   #
    # Args:                                                                    #
    #       None                                                               #
    # Result: print short usage message.                                       #
    work()
    {
        while true; do
            echo "Do some work"
            sleep $FREQUENCY
        done
    }


####----[ MAIN ]------------------------------------------------------------####

    # Retrive and check all provided arguments
    check_arguments $* || exit $?

    # Daemonize this script is proper argument was provided
    daemonize $@

    # Launch some work
    work $@
