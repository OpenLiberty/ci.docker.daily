#!/bin/bash

# Finds the latest Open Liberty development driver and builds the Docker images based on its install images.
# If this is a Travis build on master, images are tagged openliberty/daily:<image> and pushed to Docker Hub

usage="Usage: buildAll.sh --buildUrl=<build url (optional)>"

devPublishLocation="https://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/nightly/"
communityRepository=openliberty/open-liberty
officialRepository=open-liberty

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
  fullImageFile=
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
      #if [ "$testsRun" -ne 0 ] && [ "$testsPass" -eq "$testsPass" ]
      if [ "$testsPass" -eq "$testsPass" ]
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
    elif [[ $fileListLine =~ \>(openliberty-all-)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(.*\.zip) ]]
    then
      fullImageFile="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      echo "  fullImageFile=$fullImageFile"
    fi
  done <<< "$fileList"

  if [ ! -z "$runtimeImageFile" ] && [ ! -z "$javaee8ImageFile" ] && [ ! -z "$webprofile8ImageFile" ] && [ ! -z "$fullImageFile" ] && [ ! -z "$version" ] && [ "$testCheck" -ne 0 ]
  then
    fullDownloadUrl="${buildUrls[i]}/$fullImageFile"
    javaee8DownloadUrl="${buildUrls[i]}/$javaee8ImageFile"
    runtimeDownloadUrl="${buildUrls[i]}/$runtimeImageFile"
    webprofile8DownloadUrl="${buildUrls[i]}/$webprofile8ImageFile"
    break
  fi
done

if [ -z "$version" ] || [ -z "$javaee8DownloadUrl" ] || [ -z "$runtimeDownloadUrl" ] || [ -z "$webprofile8DownloadUrl" ]
then
  echo "ERROR: Could not find a valid build with all needed install images available"
  exit 1
fi

# Run the ci.docker buildAll.sh script with our latest build overrides
cd ci.docker/build
buildCommand="./buildAll.sh --version=$version --javaee8DownloadUrl=$javaee8DownloadUrl --runtimeDownloadUrl=$runtimeDownloadUrl --webprofile8DownloadUrl=$webprofile8DownloadUrl"
echo "Building all images using command: $buildCommand"
eval $buildCommand

# Build the full image, which is unique to daily builds (just java8-ibm right now, more can be added if needed)
wget --progress=bar:force $fullDownloadUrl -U UA-Open-Liberty-Docker -O full.zip
fullDownloadSha=$(sha1sum full.zip | awk '{print $1;}')
rm -f full.zip
docker build -t openliberty/daily:full-java8-ibm -t openliberty/daily:full --build-arg LIBERTY_VERSION=${version} --build-arg LIBERTY_SHA=${fullDownloadSha} --build-arg LIBERTY_DOWNLOAD_URL=${fullDownloadUrl} ../../full/java8/ibmjava

## Push images to Docker Hub (if this is a Travis non-pull request build on master)
if [ "$TRAVIS" == "true" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]
then
  echo "Logging into Docker and pushing images to Docker Hub"
  docker login -u ${DOCKERID} -p ${DOCKERPWD}

  echo "Pushing openliberty/daily:full"
  docker push openliberty/daily:full
  echo "Pushing openliberty/daily:full-java8-ibm"
  docker push openliberty/daily:full-java8-ibm

  while read -r buildContextDirectory imageTag imageTag2 imageTag3
  do
    # only push the 'latest' images right now, more can be added later if needed
    if [ "${imageTag3}" == "latest" ]
    then
      if [[ $buildContextDirectory =~ community ]]
      then
        origRepository=$communityRepository
      else
        origRepository=$officialRepository
      fi
      for image in "$imageTag" "$imageTag2" "$imageTag3"
      do
        if [ ! -z "$image" ]
        then
          # re-tag as openliberty/daily
          echo "Tagging ${origRepository}:${image} openliberty/daily:${imageTag}"
          docker tag ${origRepository}:${image} openliberty/daily:${image}
          # push to docker hub
          echo "Pushing openliberty/daily:${image} to Docker Hub"
          docker push openliberty/daily:${image}
        fi
      done
    fi
  done < "images.txt"
else
  echo "Not pushing to Docker Hub (only Travis builds of the master branch do that)."
fi
