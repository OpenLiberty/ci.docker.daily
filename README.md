[![Build Status](https://travis-ci.org/OpenLiberty/ci.docker.daily.svg?branch=master)](https://travis-ci.org/OpenLiberty/ci.docker.daily)

# ci.docker.daily
Daily development builds of the Open Liberty Docker images.

Uses the build scripts and Dockerfiles from submodule https://github.com/OpenLiberty/ci.docker 
to build the Open Liberty Docker images, sending in arguments to override the install image 
download details to use the latest development builds published at
http://public.dhe.ibm.com/ibmdl/export/pub/software/openliberty/runtime/nightly/ instead of 
the official images on Maven Central.
