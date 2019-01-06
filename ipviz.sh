#!/usr/bin/env bash
readonly BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
readonly PROGRAM="$(basename "${BASH_SOURCE[0]}")"

# Fail on any errors
set -o errexit
# Enforce variable init
set -o nounset

usage() {
    cat << EOF
Transforms a list of subnets with allocated ips in a simple heatmap png
=======================================================================
usage: $PROGRAM [OPTIONS] [-c cidr_limit] [-o output_png] input_json

OPTIONS:
    -d : Debug output
    -? : This message
    -c CIDR
       Limit the output to this CIDR
       Default to /16 subnet of the lowest IP in input
    -o output_png
       defaults to heatmap_<baseip_of_cidr>.png
input_json:
    file with json array and the following object structure:
    [
      {
        "cidr": "10.107.0.0/28",
        "available_ips": 5,
        "name": "public az1"
      },
      {
        "cidr": "10.107.0.64/28",
        "available_ips": 2,
        "name": "public az2"
      }
    ]

* each subnet is rendered as a block in the heatmap
* the allocated ips in a subnet are filled from left/top to right/down
* the free ips are rendered with a random background color in the block

Required tools installed:
 - ipv4-heatmap "make install" from: https://github.com/measurement-factory/ipv4-heatmap
 - jq
 - imagemagick
 - ipcalc
 - prips

EOF
}

main() {
    parse_arguments $@
    local readonly input="${ARG_PARAMETERS[0]:-}"
    declare -a args
    if [[ ${#ARG_PARAMETERS[@]} -gt 1 ]]; then
        args=("${ARG_PARAMETERS[@]:1}")
    else
        # Workaround: bash assumes empty arrays as unset. WTF. Fixed in bash 4.4
        args=("")
    fi

    validate_input_file "${input}"
    process "${input}" "${OUTPUT_FILE_ARG:-}" "${CIDR_TO_RENDER_ARG:-}" "${args}"
}

validate_input_file () {
    local readonly input="${1}"
    if [[ -z ${input} ]]; then
        usage
        error "Error: *** input file is missing"
        exit 1
    fi

    if [[ ! -f ${input} ]]; then
        usage
        error "Error: *** input file ${input} not found"
        exit 1
    fi
}

# Makes a 16 CIDR based on the smallest IP in the subnet list
best_guess_cidr() {
    local readonly used_ips="${1}"
    firstip=$(echo -e "${used_ips}" | head -n 1)
    ipcalc -nb "${firstip}/16" | awk '/Network/ {print $2}'
}

process() {
    local readonly subnets_input_file="${1}"
    local readonly outputfile_arg="${2:-}"
    local readonly cidr_to_render_arg="${3:-}"

    # Step 1: Make IP List
    local readonly used_ips=$(echo -e "$(makeUsedIps "${subnets_input_file}")" | sort)

    # Step 2: prepare the cidr for rendering
    local readonly cidr_to_render="${cidr_to_render_arg:-$(best_guess_cidr "${used_ips}")}"
    local readonly baseip=${cidr_to_render%%/*}
    local readonly rangebits=${cidr_to_render##*/}

    local readonly check="$(echo "$baseip" | grepcidr "${cidr_to_render}" 2>/dev/null)"
    if [[ -z ${check} ]]
    then
        error "Parameter error: '${cidr_to_render}' is not a valid cidr"
        exit 1
    fi

    # Step 3: Prepare output file
    local readonly outputfile="${outputfile_arg:-heatmap_${baseip}.png}"
    inf "Processing '${subnets_input_file}' with cidr limit '${baseip}/${rangebits}' and write to '${outputfile}'"

    local readonly annotations=$(echo -e "$(makeAnnotations "${subnets_input_file}")")
    local readonly shades=$(echo -e "$(makeShades "${subnets_input_file}")")

    used_ip_count=$(echo -e "$used_ips" | wc -l)
    subnet_count=$(echo -e "$annotations" | wc -l)

    inf "Generating heatmap with ${used_ip_count} IPs in ${subnet_count} subnets"
    # Generate heatmap
    echo -e "${used_ips}" | \
        ipv4-heatmap \
            -a <(echo -e "${annotations}") \
            -s <(echo -e "${shades}") \
            -f "Helvetica-12" \
            -y "${cidr_to_render}" \
            -o "${outputfile}" \
            -z 0 \
            -m \
            -r
    local readonly heatmapsize="800x800"
    inf "Resize heatmap to ${heatmapsize}"
    convert "${outputfile}" \
        -resize "${heatmapsize}" \
        "${outputfile}"
    inf "Enhance image with parameter title and border"
    montage \
        -label "${used_ip_count} ips allocated in ${subnet_count} subnets of ${cidr_to_render} - $(LANG=de_DE date)"\
        -pointsize 18 \
        -frame 5 -geometry +0+0 \
        "${outputfile}" \
        "${outputfile}"
    inf "File '${outputfile}' generated"
}

getCidr() {
    echo ${1} | jq -r '.cidr // empty'
}

getName() {
    echo ${1} | jq -r '.name // empty'
}

getAvailable() {
    echo ${1} | jq -r '.available_ips // empty'
}

randomCidrColor() {
    echo "0x$(openssl rand -hex 3)"
}

calcIPsInCidr() {
    local readonly cidr="${1}"
    ipcalc -b "${cidr}" | awk '/Hosts\/Net/ {print $2}'
}

# Create the ipv4-heatmap annotation file (names for cidr ranges)
makeAnnotations() {
    local readonly subnet_file=${1}
    jq -c '.[]' ${subnet_file} | while read subnet; do
        local readonly cidr=$(getCidr "${subnet}")
        local readonly name=$(getName "${subnet}")
        echo "${cidr}\t${name}"
    done
}

# Create the ipv4-heatmap shades file (background for cidr ranges)
makeShades() {
    local readonly subnet_file=${1}
    jq -c '.[]' ${subnet_file} | while read subnet; do
        local readonly cidr=$(getCidr "${subnet}")
        echo "${cidr}\t$(randomCidrColor)\t96"
    done
}

# Create the ipv4-heatmap ip list (list of used ips in all subnets)
makeUsedIps() {
    local readonly subnet_file=${1}
    jq -c '.[]' "${subnet_file}" | while read subnet; do
        local readonly cidr=$(getCidr "${subnet}")
        local readonly name=$(getName "${subnet}")
        local readonly available=$(getAvailable "${subnet}")
        local readonly total=$(calcIPsInCidr "$cidr")
        local readonly used=$((2 + total - available))
        # Generate a list of <n> IPs from a cidr
        prips "${cidr}" | head -n "${used}"
    done
}

parse_arguments() {
    # check command line arguments
    local OPTION OPTARG
    while getopts "?hdc:o:" OPTION
    do
        case "${OPTION}" in
            \? | h )
                usage
                exit 0
            ;;
            d)
                LOG_LEVEL=${LOGLEVEL_DEBUG}
            ;;
            c)
                CIDR_TO_RENDER_ARG="${OPTARG}"
            ;;
            o)
                OUTPUT_FILE_ARG="${OPTARG}"
            ;;
        esac
    done
    shift $((OPTIND - 1))

    # All other arguments
    ARG_PARAMETERS=($@)
}



init_logging() {
    exec 3>&2 # logging stream (file descriptor 3) defaults to STDERR
    LOG_LEVEL=${LOG_LEVEL:-4} # default to show info
    LOGLEVEL_SILENT=0
    LOGLEVEL_CRITICAL=1
    LOGLEVEL_ERROR=2
    LOGLEVEL_WARNING=3
    LOGLEVEL_INFO=4
    LOGLEVEL_DEBUG=5
}

# Maximum length of separator line
linewidth() {
    # line - length of iso8601 date - length log level column - database
    printf '%d' $(($(maxwidth) - 25 - 18 - 10))
}

# Get a line of terminal width minus logging prefix. $1: Line character
line() {
    printf '%*s' "$(linewidth)" '' | tr ' ' "${1:--}"
}

# Maximum length of logging line
maxwidth() {
    local width=0
    if tput cols 2>&1 > /dev/null; then
        width=$((${COLUMNS:-$(tput cols)} - 4))
    fi
    # 0: in case of error
    width=$(( width = 0 ? 400 : ${width}))
    # Max in case of jenkins build
    if [[ ! -z ${JENKINS_URL:-} ]]; then
      width=400
    fi
    # Minimum 40
    printf '%d' $(( width < 40 ? 40 : ${width} ))
}

notify() { log $LOGLEVEL_SILENT "$1"; }
# Always prints
critical() { log $LOGLEVEL_CRITICAL "$1"; }
error() { log $LOGLEVEL_ERROR "$1"; }
warn() { log $LOGLEVEL_WARNING "$1"; }
# "info" is already a command
inf() { log $LOGLEVEL_INFO "$1"; }
inf_nonewline() { log $LOGLEVEL_INFO "$1" "-n"; }
debug() { log $LOGLEVEL_DEBUG "$1"; }
loglevelpad() {
    printf "[%s]" "$1"
}

log() {
    declare -A loglevelnames
    # Achtung: Der IntelliJ Formatter macht den folgenden Code kaputt. Leider schützt auch die formatter:off Markierung nicht
    # Es dürfen keine Blanks in den Zeilen sein!
    # @formatter:off
    loglevelnames[$LOGLEVEL_SILENT]='${WHITE}NOTE${NC}'
    loglevelnames[$LOGLEVEL_CRITICAL]="${RED}CRIT${NC}"
    loglevelnames[$LOGLEVEL_ERROR]="${RED}ERROR${NC}"
    loglevelnames[$LOGLEVEL_WARNING]="${YELLOW}WARN${NC}"
    loglevelnames[$LOGLEVEL_INFO]="${WHITE}INFO${NC}"
    loglevelnames[$LOGLEVEL_DEBUG]="DEBUG"

    if ! [[ ${LOG_LEVEL} =~ ^[0-9]+$ ]] ; then
        local readonly wrong_value=${LOG_LEVEL}
        # Wrong log level. Default to info
        LOG_LEVEL="${LOGLEVEL_INFO}"
        warn "Log level ${wrong_value} not valid. Reset to ${LOG_LEVEL}"
    fi
    # @formatter:on
    if [[ ${LOG_LEVEL} -ge $1 ]]; then
        local readonly datestring=$(date +'%Y-%m-%dT%H:%M:%S%z')
        # Expand escaped characters, wrap at maxwidth chars, indent wrapped lines
        echo -e "${3:-}" \
 "${datestring} $(loglevelpad ${loglevelnames[$1]}) $2" | \
 fold -w$(maxwidth) -s | \
 sed '2~1s/^/  /' >&3
    fi
}

init_colors() {
    readonly WHITE='\033[1;37m'
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[0;33m'
    readonly CYAN='\033[0;36m'
    readonly LIGHT_CYAN='\033[0;96m'
    readonly GREEN='\033[0;32m'
    readonly LIGHT_GREEN='\033[0;92m'
    readonly NC='\033[0m' # No Color
}

init_colors
init_logging

START_TIME=$SECONDS
main $@
ELAPSED_TIME=$(($SECONDS - $START_TIME))
inf "$PROGRAM finished in ${ELAPSED_TIME}s"
