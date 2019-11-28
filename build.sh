#!/bin/bash

# Builds all of the latest Open Liberty Docker images
#  values set below, or in arguments, will override the defaults set in the Dockerfiles, allowing for development builds
#  By default this will not build the versioned images (non-latest versions), but this can be enabled by using the --buildVersionedImages.
set -Eeo pipefail

readonly usage="Usage: build.sh --version=<version> --buildLabel=<build label> --fullDownloadUrl=<fulldownload image download url>"

readonly IMAGE_ROOT="releases" # the name of the dir holding all versions
readonly REPO="openliberty/daily"
readonly LOCAL_REPO="daily"
readonly LATEST_TARGET="full-java8-openj9-ubi"

main () {
    # values above can be overridden by optional arguments when this script is called
    while [ $# -gt 0 ]; do
    case "$1" in
        --version=*)
        version="${1#*=}"
        ;;
        --buildLabel=*)
        buildLabel="${1#*=}"
        ;;
        --fullDownloadUrl=*)
        fullDownloadUrl="${1#*=}"
        ;;
        *)
        echo "Error: Invalid argument - $1"
        echo "$usage"
        exit 1
    esac
    shift
    done

    if [[ -z "${buildLabel}" || -z "${fullDownloadUrl}" || -z "${version}" ]]; then
      echo "Error: buildLabel, fullDownloadUrl, and version are required flags"
      echo "${usage}"
      exit 1
    fi

    wget --progress=bar:force $fullDownloadUrl -U UA-Open-Liberty-Docker -O full.zip
    fullDownloadSha=$(sha1sum full.zip | awk '{print $1;}')
    rm -f full.zip

    ## Check if master build and define docker push bool accordingly
    push="false"
    if [[ "$TRAVIS" = "true" && "$TRAVIS_PULL_REQUEST" = "false" && "$TRAVIS_BRANCH" = "master" ]]; then
        push="true"
        echo "$DOCKERPWD" | docker login -u "$DOCKERID" --password-stdin
    fi

    local tags=(kernel)

    for tag in "${tags[@]}"; do
      build_latest_tag $tag
    done
    # create the latest tag for default pulls
    echo "****** Pushing tag ${LATEST_TARGET} as latest"
    tag_latest
}

## build the latest version of open liberty which has the new tag system
build_latest_tag() {
    local version="latest"
    local tag="$1"
    local tag_label="full"
    # set image information arrays
    local file_exts_ubi=(adoptopenjdk8 adoptopenjdk11 adoptopenjdk13 ibmjava8)
    local tag_exts_ubi=(java8-openj9-ubi java11-openj9-ubi java13-openj9-ubi java8-ibmjava-ubi)

    for i in "${!tag_exts_ubi[@]}"; do
        local docker_dir="${IMAGE_ROOT}/${version}/${tag}"
        local full_path="${docker_dir}/Dockerfile.ubi.${file_exts_ubi[$i]}"
        if [[ -f "${full_path}" ]]; then
            local build_image="${REPO}:${tag_label}-${tag_exts_ubi[$i]}"

            echo "****** Building image ${build_image}..."
            docker build --no-cache=true -t "${build_image}" -f "${full_path}" --build-arg LIBERTY_VERSION=${version} --build-arg LIBERTY_BUILD_LABEL=${buildLabel} --build-arg LIBERTY_SHA=${fullDownloadSha} --build-arg LIBERTY_DOWNLOAD_URL=${fullDownloadUrl} "${docker_dir}"
            handle_results $? "${build_image}"
        else
            echo "Could not find Dockerfile at path ${full_path}"
            exit 1
        fi
    done

    local docker_dir="${IMAGE_ROOT}/${version}/${tag}"
    local full_path="${docker_dir}/Dockerfile.ubuntu.adoptopenjdk8"

    if [[ -f "${full_path}" ]]; then
        local ubuntu_image="${REPO}:${tag_label}-adoptopenjdk8"

        echo "****** Building image ${ubuntu_image}..."
        docker build --no-cache=true -t "${ubuntu_image}" -f "${full_path}" --build-arg LIBERTY_VERSION=${version} --build-arg LIBERTY_BUILD_LABEL=${buildLabel} --build-arg LIBERTY_SHA=${fullDownloadSha} --build-arg LIBERTY_DOWNLOAD_URL=${fullDownloadUrl} "${docker_dir}" 
        handle_results $? "${ubuntu_image}"
    else
        echo "Could not find Dockerfile at path ${full_path}"
        exit 1
    fi
}

## push the built image if build was successful and branch is master
handle_results () {
  local rc="$1"; shift
  local image="$1"
  if [[ $rc -ne 0 ]]; then
    echo "Error building ${image}, exiting."
    exit $rc
  fi
  ## push inprogress image for the manifest tool to aggregate
  if [[ "$push" = "true" ]]; then
    echo "****** Pushing ${image}..."
    docker push ${image}
  else
    echo "Not pushing to Docker Hub because this is not a production build of the master branch"
  fi
}

## create the latest tag for default pull
tag_latest() {
  if [[ "${push}" = "true" ]]; then
    docker tag "${REPO}:${LATEST_TARGET}" "${REPO}:latest"
    docker push "${REPO}:latest"
  else
    echo "****** Skipping push of latest tag as this is not a master build"
  fi
}

main $@