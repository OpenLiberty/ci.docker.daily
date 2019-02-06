#!/bin/bash

# Finds the latest Open Liberty development driver and builds the Docker images based on its install images.

usage="Usage: buildAll.sh --buildUrl=<build url (optional)>"

devPublishLocation="https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/nightly/"

# values above can be overridden by optional arguments when this script is called
while [ $# -gt 0 ]; do
  case "$1" in
    --buildUrl=*)
      buildUrl="${1#*=}"
      ;;
    *)
      echo "Error: Invalid argument - $1"
      echo "$usage"
      exit 1
  esac
  shift
done

if [ -z "$buildUrl" ]
then
  # List the published builds available in $devPublishLocation
  buildList=$(curl -s "$devPublishLocation" | grep folder.gif)
  buildUrls=()

  # parse out the build directory name
  while read -r buildListLine
  do
    if [[ $buildListLine =~ .*([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}).* ]]
    then
      buildUrls+=("${devPublishLocation}${BASH_REMATCH[1]}")
    fi
  done <<< "$buildList"
else
  buildUrls[0]=$buildUrl
fi

# loop through build directories in reverse order
for (( i=${#buildUrls[@]}-1 ; i>=0 ; i-- ))
do
  testCheck=0
  allImageFile=
  version=
  echo "Checking build ${buildUrls[i]}"
  # check the files published for the build
  fileList=$(curl -s "${buildUrls[i]}/" | egrep "openliberty|info.json")
  while read -r fileListLine
  do
    # if we find the info.json file for this build, download it and check that tests ran and they all passed
    if [[ $fileListLine =~ info.json ]]
    then
      # download the info.json, make sure tests ran and they all passed
      testsRun=0
      testsPass=0
      infoJson=$(curl -s "${buildUrls[i]}/info.json" | grep test)
      while read -r jsonLine
      do
        if [[ $jsonLine =~ \"test_passed\":[[:blank:]]\"([0-9]+)\" ]]
        then
          testsPass=${BASH_REMATCH[1]}
          echo "  testsPass=$testsPass"
        elif [[ $jsonLine =~ \"total_tests\":[[:blank:]]\"([0-9]+)\" ]]
        then
          testsRun=${BASH_REMATCH[1]}
          echo "  testsRun=$testsRun"
        fi
      done <<< "$infoJson"
      if [ "$testsRun" -ne 0 ] && [ "$testsPass" -eq "$testsPass" ]
      then
        testCheck=1
      fi
    elif [[ $fileListLine =~ \>(openliberty-all-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(.*\.zip) ]]
    then
      allImageFile="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      version="${BASH_REMATCH[2]}"
      echo "  allImageFile=$allImageFile"
      echo "  version=$version"
    fi
  done <<< "$fileList"

  if [ ! -z "$allImageFile" ] && [ ! -z "$version" ] && [ "$testCheck" -ne 0 ]
  then
    javaee8DownloadUrl="${buildUrls[i]}/$allImageFile"
    runtimeDownloadUrl="${buildUrls[i]}/$allImageFile"
    webprofile8DownloadUrl="${buildUrls[i]}/$allImageFile"
    break
  fi
  # check that the install files we need are available for this build
done

if [ -z "$version" ] || [ -z "$javaee8DownloadUrl" ] || [ -z "$runtimeDownloadUrl" ] || [ -z "$webprofile8DownloadUrl" ]
then
  echo "ERROR: Could not find a valid build with all needed install images available"
  exit 1
fi

cd ci.docker/build
buildCommand="./buildAll.sh --version=$version --communityRepository=open-liberty-daily --officialRepository=open-liberty-daily --javaee8DownloadUrl=$javaee8DownloadUrl --runtimeDownloadUrl=$runtimeDownloadUrl --webprofile8DownloadUrl=$webprofile8DownloadUrl"
echo "Building all images using command: $buildCommand"
eval $buildCommand

# now publish all of the images!!!
