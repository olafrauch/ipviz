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
usage: $PROGRAM [OPTIONS] [-c cidr_limit] [-o output_png] [-t aws|simple] input_json|STDIN

OPTIONS:
    -d : Debug output
    -? : This message
    -t : Input format type:
          AWS (default): Format as aws ec2 describe-subnets --output json
          SIMPLE : Format see below
    -c CIDR
       Limit the output to this CIDR
       Default to /16 subnet of the lowest IP in input
    -o output_png
       defaults to heatmap_<baseip_of_cidr>.png
    -r : Export input file as enhanced output file compatible with SIMPLE File format

input_json:
    file or stdin with json array and the following object structure:
    SIMPLE:
    [
      {
        "cidr": "10.107.0.0/28",
        "available": 5,
        "name": "public az1",
        "az": "eu-central-1"
      },
      {
        "cidr": "10.107.0.64/28",
        "available": 2,
        "name": "public az2",
        "az": "eu-central-1"
      }
    ]
 or
    AWS:
    Output as in aws ec2 describe-subnets ...

* each subnet is rendered as a block in the heatmap
* the allocated ips in a subnet are filled from left/top to right/down
* the free ips are rendered with a random background color in the block

Required tools:
 - ipv4-heatmap "make install" from: https://github.com/measurement-factory/ipv4-heatmap
 - jq
 - imagemagick
 - ipcalc
 - prips
 - grepcidr

EOF
}

main() {
    validate_environment
    parse_arguments $@
    local readonly inputfile_arg="${ARG_PARAMETERS[0]:-/dev/stdin}"
    declare -a args
    if [[ ${#ARG_PARAMETERS[@]} -gt 1 ]]; then
        args=("${ARG_PARAMETERS[@]:1}")
    else
        # Workaround: bash assumes empty arrays as unset. WTF. Fixed in bash 4.4
        args=("")
    fi

    debug "Working directory $(pwd)"
    validate_inputfile_arg "${inputfile_arg}"
    process "${inputfile_arg}" "${OUTPUT_FILE_ARG:-}" "${CIDR_TO_RENDER_ARG:-}" "${INPUT_FORMAT_TYPE_ARG:-aws}" "${args}"
}

validate_environment() {
    check_program "jq"
    check_program "convert"
    check_program "ipcalc"
    check_program "prips"
    check_program "grepcidr"
    check_program "ipv4-heatmap"
}

check_program() {
    local readonly program="$1"
    if command -v ${program} >/dev/null; then
        debug "Check: ${program} is installed : $(which ${program})"
    else
        error "Check failed: ${program} is not installed"
        exit 1
    fi
}

validate_inputfile_arg () {
    local readonly input="${1}"
    if [[ -z ${input} ]]; then
        usage
        error "Error: *** input file is missing."
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
    local readonly inputfile_arg="${1}"
    local readonly outputfile_arg="${2:-}"
    local readonly cidr_to_render_arg="${3:-}"
    local readonly input_format="${4:-}"

    debug "Input data mode : ${input_format}"

    local readonly input=$(cat "${inputfile_arg}")
    # Step 1: Make IP List (newline separated)
    local readonly used_ips=$(echo -e "$(makeIPListOfUsedIPs "${input}" "${input_format}")" | sort)

    # Step 2: prepare the cidr for rendering
    local readonly cidr_to_render="${cidr_to_render_arg:-$(best_guess_cidr "${used_ips}")}"
    local readonly baseip=${cidr_to_render%%/*}
    local readonly rangebits=${cidr_to_render##*/}

    local readonly check="$(echo "$baseip" | grepcidr "${cidr_to_render}" 2>/dev/null)"
    if [[ -z ${check} ]]
    then
        error "Parameter error: '${cidr_to_render}' is not a valid cidr ($check)"
        exit 1
    fi

    # Step 3: Prepare output file
    local readonly output_heatmap="${outputfile_arg:-heatmap_${baseip}.png}"
    local readonly output_basename=${output_heatmap%.*}
    local readonly output_report="${output_basename}_simple.json"

    inf "Processing '${inputfile_arg}' in ${input_format} format with cidr limit '${baseip}/${rangebits}' and write to '${output_heatmap}'"

    local readonly annotations=$(echo -e "$(makeAnnotations "${input}" "${input_format}")")
    local readonly shades=$(echo -e "$(makeShades "${input}" "${input_format}")")

    debug "Sample shades:\n$(echo -e "${shades}" | head -n 15)"
    debug "Sample annotations:\n$(echo -e "${annotations}" | head -n 15)"
    debug "Sample ips:\n$(echo -e "${used_ips}" | head -n 15)"

    # Export report
    if [[ "${EXPORT_REPORT_ARG:-false}" == "true" ]]; then
        inf "Exporting the input file ${inputfile_arg} (${input_format}) as enhanced json in simple format to ${output_report}"
        makeReport "${input}" "${input_format}" "${output_report}"
    fi

    local readonly used_ip_count=$(echo -e "${used_ips}" | wc -l)
    local readonly subnet_count=$(echo -e "${annotations}" | wc -l)

    inf "Generating heatmap with ${used_ip_count} IPs in ${subnet_count} subnets"
    # Generate heatmap
    echo -e "${used_ips}" | \
        ipv4-heatmap \
            -a <(echo -e "${annotations}") \
            -s <(echo -e "${shades}") \
            -f "Helvetica-12" \
            -y "${cidr_to_render}" \
            -o "${output_heatmap}" \
            -z 0 \
            -m \
            -r
    local readonly heatmapsize="800x800"
    inf "Resize heatmap to ${heatmapsize}"
    convert "${output_heatmap}" \
        -resize "${heatmapsize}" \
        "${output_heatmap}"
    inf "Enhance image with parameter title and border"
    montage \
        -label "${used_ip_count} ips allocated in ${subnet_count} subnets of ${cidr_to_render} - $(date)"\
        -pointsize 18 \
        -frame 5 -geometry +0+0 \
        "${output_heatmap}" \
        "${output_heatmap}"
    inf "File '${output_heatmap}' generated"
}

makeReport(){
    local readonly input="${1}"
    local readonly input_format="${2}"
    local readonly output_file="${3}"
    assertNotEmpty "input_format" "${input_format:-}"
    assertNotEmpty "output file name" "${output_file:-}"

    list_of_objects=($(readSubnets "${input}" "${input_format}" | while read subnet; do
            echo -e "$(convertSubnet "${subnet}" | jq -c '.')"
        done
    ))
    combined_objects="$(printf ",%s" "${list_of_objects[@]}")"
    echo "[ ${combined_objects:1} ]" | jq '.'  > "${output_file}"
}

# Convert a subnet JSON
convertSubnet() {
    local readonly subnet="${1}"
    local readonly cidr=$(getCidr "${subnet}" "${input_format}")
    local readonly name=$(getName "${subnet}" "${input_format}")
    local readonly available=$(getAvailable "${subnet}" "${input_format}")
    local readonly total=$(( $(countIPsInCidr "$cidr") + 2 ))
    local readonly used=$((total - available))
    local readonly az=$(getAZ "${subnet}" "${input_format}")
    list_of_attributes=(
        $(jsonAttribute "name" "${name}")
        $(jsonAttribute "cidr" "${cidr}")
        $(jsonAttribute "az" "${az}")
        $(jsonAttribute "available" "${available}")
        $(jsonAttribute "total" "${total}")
        $(jsonAttribute "used" "${used}")
        $(jsonAttribute "usage_percent" "$(( 100 * used / total ))")
    )
    all_attributes="$(printf ",%s" "${list_of_attributes[@]}")"
    echo "{ ${all_attributes:1} }" | jq -c '.'
}

jsonAttribute() {
    echo "\"$1\":\"$2\""
}

getCidr() {
    local readonly subnet="${1}"
    local readonly input_format="${2}"

    assertNotEmpty "subnet json object" "${subnet:-}"
    assertNotEmpty "input_format" "${input_format:-}"

    case "${input_format,,}" in
        "aws" )
            echo "${subnet}" | jq -r '.CidrBlock // empty'
        ;;
        "simple" | "" )
            echo "${subnet}" | jq -r '.cidr // empty'
        ;;
        *)
            error "Unknown input format '${input_format}'"
            exit 1
        ;;
    esac
}

getName() {
    local readonly subnet="${1}"
    local readonly input_format="${2}"
    assertNotEmpty "subnet json object" "${subnet:-}"
    assertNotEmpty "input_format" "${input_format:-}"
    case "${input_format,,}" in
        "aws" )
            echo "${subnet}" | jq -r '.Tags[] | select(.Key | contains("Name")) | .Value // empty'
        ;;
        "simple" | "" )
            echo "${subnet}" | jq -r '.name // empty'
        ;;
        *)
            error "Unknown input format '${input_format}'"
            exit 1
        ;;
    esac
}

getAZ() {
    local readonly subnet="${1}"
    local readonly input_format="${2}"
    assertNotEmpty "subnet json object" "${subnet:-}"
    assertNotEmpty "input_format" "${input_format:-}"
    case "${input_format,,}" in
        "aws" )
            echo "${subnet}" | jq -r '.AvailabilityZone // empty'
        ;;
        "simple" | "" )
            echo "${subnet}" | jq -r '.az // empty'
        ;;
        *)
            error "Unknown input format '${input_format}'"
            exit 1
        ;;
    esac
}


getAvailable() {
    local readonly subnet="${1}"
    local readonly input_format="${2}"
    assertNotEmpty "subnet json object" "${subnet:-}"
    assertNotEmpty "input_format" "${input_format:-}"
    case "${input_format,,}" in
        "aws" )
            echo "${subnet}" | jq -r '.AvailableIpAddressCount // empty'
        ;;
        "simple" | "" )
            echo "${subnet}" | jq -r '.available // empty'
        ;;
        *)
            error "Unknown input format '${input_format}'"
            exit 1
        ;;
    esac
}

randomCidrColor() {
    echo "0x$(openssl rand -hex 3 2>/dev/null)"
}

countIPsInCidr() {
    local readonly cidr="${1}"
    ipcalc -b "${cidr}" | awk '/Hosts\/Net/ {print $2}'
}

# Create the ipv4-heatmap annotation file (names for cidr ranges)
makeAnnotations() {
    local readonly input="${1}"
    local readonly input_format="${2}"
    readSubnets "${input}" "${input_format}" | while read subnet; do
        local readonly cidr="$(getCidr "${subnet}" "${input_format}")"
        local readonly name="$(getName "${subnet}" "${input_format}")"
        echo "${cidr}\t${name}"
    done
}

# Create the ipv4-heatmap shades file (background for cidr ranges)
makeShades() {
    local readonly input="${1}"
    local readonly input_format="${2}"
    readSubnets "${input}" "${input_format}" | while read subnet; do
        local readonly cidr=$(getCidr "${subnet}" "${input_format}")
        echo "${cidr}\t$(randomCidrColor)\t96"
    done
}

readSubnets() {
    local readonly input="${1}"
    local readonly input_format="${2}"
    case "${input_format,,}" in
        "aws" )
            echo "${input}" | jq -c '.[] | .[]'
        ;;
        "simple" | "" )
            echo "${input}" | jq -c '.[]'
        ;;
        *)
            error "Unknown input format '${input_format}'"
            exit 1
        ;;
    esac
}

# Create the ipv4-heatmap ip list (list of used ips in all subnets)
makeIPListOfUsedIPs() {
    local readonly input="${1}"
    local readonly input_format="${2}"
    readSubnets "${input}" "${input_format}" | while read subnet; do
        local readonly cidr="$(getCidr "${subnet}" "${input_format}")"
        local readonly name="$(getName "${subnet}" "${input_format}")"
        local readonly available=$(getAvailable "${subnet}" "${input_format}")
        local readonly total=$(( $(countIPsInCidr "$cidr") + 2 ))
        local readonly used=$((total - available))
        inf "Processing '${name}' with CIDR '${cidr}'"
        debug " total IPs: ${total}"
        debug " available IPs: ${available}"
        debug " used IPs: ${used}"
        assertNotEmpty "cidr" "${cidr:-}"

        if (( ${used} > ${total} )); then
            warn "CIDR ${cidr} invalid used (${used}) > total (${total})"
        fi
        # Generate a list of <n> IPs from a cidr
        debug "Generating ip list with ${used} ip addresses in cidr ${cidr}"
        # nmap -sL ${cidr} | grep "Nmap scan report" | awk '{print $NF}' | head -n "${used}"
        prips ${cidr} | head -n "${used}"
        debug "IP list generated"
    done
}

parse_arguments() {
    # check command line arguments
    local OPTION OPTARG
    while getopts "?hdrc:o:t:" OPTION
    do
        case "${OPTION}" in
            \? | h )
                usage
                exit 0
            ;;
            d)
                LOG_LEVEL=${LOGLEVEL_DEBUG}
            ;;
            r)
                EXPORT_REPORT_ARG=true
            ;;
            c)
                CIDR_TO_RENDER_ARG="${OPTARG}"
            ;;
            o)
                OUTPUT_FILE_ARG="${OPTARG}"
            ;;
            t)
                INPUT_FORMAT_TYPE_ARG="${OPTARG}"
            ;;
        esac
    done
    shift $((OPTIND - 1))

    # All other arguments
    ARG_PARAMETERS=($@)
}


required_arg() {
    required_value "${1}" "${2}" "Missing argument"
}

assertNotEmpty() {
    required_value "${1}" "${2}" "Internal error. Value missing for:"
}

required_value() {
    local readonly name="${1:-}"
    local readonly value="${2:-}"
    local readonly message="${3:-"Missing value for"}"
    if [[ -z "${value}" ]]
    then
        error "${message} '${name}'"
        exit 1
    fi
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
        echo -e "${3:-}" "${datestring} $(loglevelpad ${loglevelnames[$1]}) $2" | sed '2~1s/^/  /' >&3
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
