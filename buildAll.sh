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
  runtimeImageFile=
  javaee8ImageFile=
  webprofile8ImageFile=
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
    elif [[ $fileListLine =~ \>(openliberty-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(.*\.zip) ]]
    then
      runtimeImageFile="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      version="${BASH_REMATCH[2]}"
      echo "  runtimeImageFile=$runtimeImageFile"
      echo "  version=$version"
    elif [[ $fileListLine =~ \>(openliberty-javaee8-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(.*\.zip) ]]
    then
      javaee8ImageFile="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      echo "  javaee8ImageFile=$javaee8ImageFile"
    elif [[ $fileListLine =~ \>(openliberty-webProfile8-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(.*\.zip) ]]
    then
      webprofile8ImageFile="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      echo "  webprofile8ImageFile=$webprofile8ImageFile"
    fi
  done <<< "$fileList"

  if [ ! -z "$runtimeImageFile" ] && [ ! -z "$javaee8ImageFile" ] && [ ! -z "$webprofile8ImageFile" ] && [ ! -z "$version" ] && [ "$testCheck" -ne 0 ]
  then
    javaee8DownloadUrl="${buildUrls[i]}/$javaee8ImageFile"
    runtimeDownloadUrl="${buildUrls[i]}/$runtimeImageFile"
    webprofile8DownloadUrl="${buildUrls[i]}/$webprofile8ImageFile"
    break
  fi
  # check that the install files we need are available for this build
done

if [ -z "$version" ] || [ -z "$javaee8DownloadUrl" ] || [ -z "$runtimeDownloadUrl" ] || [ -z "$webprofile8DownloadUrl" ]
then
  echo "ERROR: Could not find a valid build with all needed install images available"
  exit 1
fi

# Run the ci.docker buildAll.sh script with our latest build overrides
cd ci.docker/build
buildCommand="./buildAll.sh --version=$version --communityRepository=openliberty/daily --officialRepository=openliberty/daily --javaee8DownloadUrl=$javaee8DownloadUrl --runtimeDownloadUrl=$runtimeDownloadUrl --webprofile8DownloadUrl=$webprofile8DownloadUrl"
echo "Building all images using command: $buildCommand"
eval $buildCommand

## Push images to Docker Hub (if this is a Travis non-pull request build on master)
if [ "$TRAVIS" == "true" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]
then
  echo "Logging into Docker and pushing images to Docker Hub"
  docker login -u ${DOCKERID} -p ${DOCKERPWD}
  while read -r buildContextDirectory imageTag imageTag2 imageTag3
  do
    # only push the 'latest' images right now, more can be added later if needed
    if [ "${imageTag3}" == "latest" ]
    then
      echo "Pushing openliberty/daily:${imageTag} to Docker Hub"
      docker push openliberty/daily:${imageTag}
      if [ ! -z "${imageTag2}" ]
      then
        echo "Pushing openliberty/daily:${imageTag2} to Docker Hub"
        docker push openliberty/daily:${imageTag2}
        if [ ! -z "${imageTag3}" ]
        then
          echo "Pushing openliberty/daily:${imageTag3} to Docker Hub"
          docker push openliberty/daily:${imageTag3}
        fi
      fi
    fi
  done < "images.txt"
else
  echo "Not pushing to Docker Hub (only Travis builds of the master branch do that)."
fi
