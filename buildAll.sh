#!/bin/bash

# Finds the latest Open Liberty development driver and builds the Docker images based on its install images.
# If this is a Travis build on master, images are tagged openliberty/daily:<image> and pushed to Docker Hub

set -e

readonly usage="Usage: buildAll.sh"

readonly NIGHTLY_URL="https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/nightly/"

main () {
    ## build ibmjava base image
    build_ubi_base
    ## Fetch list of urls
    local urls=$(fetch_liberty_urls)
    urls=($urls)
    ## Loop through list in reverse order, break on valid build
    local args
    for (( i=${#urls[@]}-1 ; i>=0 ; i-- )); do
        echo "****** Parsing url: ${urls[i]}"
        args=$(parse_build_url "${urls[i]}")
        # if args is not empty string build was successful
        if [[ ! -z "${args}" ]]; then
            args=($args) #convert space seperate string to arr
            break
        fi
    done
    ## Set arguments for the build script
    local fullImageUrl="${args[0]}"
    local buildLabel="${args[1]}"
    local version="${args[2]}"

    if [[ -z "${fullImageUrl}" || -z "${buildLabel}" || -z "${version}" ]]; then
        echo "ERROR: Could not find a valid build with all needed install images available"
        exit 1
    fi

    echo "****** Found latest build"
    printf "URL: %s \nLabel: %s \nVersion: %s\n" "${fullImageUrl}" "${buildLabel}" "${version}"
    cd ci.docker
    echo "****** Starting daily build from $(pwd)..."
    ../build.sh --version="${version}" --buildLabel="${buildLabel}" --fullDownloadUrl="${fullImageUrl}"
}
## builds the ibmjava base for ./build.sh script
build_ubi_base() {
  docker pull registry.access.redhat.com/ubi8/ubi
  ## pull Dockerfile from ibmjava
  mkdir java
  wget https://raw.githubusercontent.com/ibmruntimes/ci.docker/master/ibmjava/8/jre/ubi/Dockerfile -O java/Dockerfile

  ## replace references to user 1001 as we need to build as root
  sed -i.bak '/useradd -u 1001*/d' ./java/Dockerfile && sed -i.bak '/USER 1001/d' ./java/Dockerfile && rm java/Dockerfile.bak
  docker build -t ibmjava:8-ubi java
}
## @returns a list of strings representing the nightly liberty builds, old to newest
fetch_liberty_urls() {
    ## Generate Download URL, SHA, build label
    local buildList=$(curl -s "${NIGHTLY_URL}" | grep folder.gif)
    local buildUrls=()

    while read -r currentLine; do
        if is_build_link "${currentLine}"; then
            buildUrls+=("${NIGHTLY_URL}${BASH_REMATCH[1]}")
        fi
    done <<< "${buildList}"
    ## this is equivalent to returning a space seperated str of urls (iterable)
    echo "${buildUrls[@]}"
}
## @returns space seperated string if successfully, empty string on failure
parse_build_url() {
    local buildUrl="$1"
    declare fullImageFile buildLabel version output
    ## loop through items listed under build and format arguments
    fileList=$(curl -s "${buildUrl}/" | egrep "openliberty|info.json")
    while read -r current_file; do
        ## if the tests did not pass return empty output string
        if is_info_file "${current_file}" && ! is_build_success "${current_file}" "${buildUrl}"; then
            break
        elif is_full_file "${current_file}"; then
            fullImageUrl="${buildUrl}/${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[3]}.zip"
            version="${BASH_REMATCH[2]}"
            buildLabel="${BASH_REMATCH[3]}"
            output="${fullImageUrl} ${buildLabel} ${version}"
        fi
    done <<< "${fileList}"
    ## return the required build arguments for running build script
    echo "${output}"
}
## @returns status code of the test
is_build_success() {
    local info_file="$1"; shift
    local current_url="$1"
    # variables for comparison in return
    declare testsPass testsRun
    # fetch jsonfile
    local json=$(curl -s "${current_url}/info.json" | grep test)
    while read -r jsonLine; do
        if [[ $jsonLine =~ \"test_passed\":[[:blank:]]\"([0-9]+)\" ]]; then
          testsPass=${BASH_REMATCH[1]}
        elif [[ $jsonLine =~ \"total_tests\":[[:blank:]]\"([0-9]+)\" ]]; then
          testsRun=${BASH_REMATCH[1]}
        fi
    done <<< "${json}"
    ## return status
    [[ "${testsRun}" -ne 0 && "${testsPass}" -eq "${testsRun}" ]]
}

### REGEX conditionals
## Usage for all: `if is_condition <param>; then ...`
is_build_link() {
    local link_tag="$1"
    [[ $link_tag =~ .*([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}).* ]]
}
is_kernel_file() {
    local str="$1"
    [[ $str =~ \>(openliberty-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)-(.*)\.zip ]]
}
is_full_file() {
    local str="$1"

    [[ $str =~ \>(openliberty-all-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)-(.*)\.zip ]]
}
is_info_file() {
    local str="$1"

    [[ $str =~ info.json ]]
}
main