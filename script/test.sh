#!/usr/bin/env bash
set -e

PREFIX="`pwd`/install"

[ $TRAVIS_OS_NAME = 'linux' ] && MAKE_JOBS=`nproc`
[ $TRAVIS_OS_NAME = 'osx' ] && MAKE_JOBS=`sysctl -n hw.ncpu`
MAKE_JOBS+=" --quiet"

#CFLAGS="-g0 -w"
#CXXFLAGS="-g0 -w"

echo `which libtool`
libtool --version < /dev/null

export PREFIX MAKE_JOBS CC CXX CC_FOR_BUILD CXX_FOR_BUILD CFLAGS CXXFLAGS

case $TARGET in
*-msdosdjgpp) SCRIPT=./build-djgpp.sh ;;
ia16*)        SCRIPT=./build-ia16.sh ;;
avr)          SCRIPT=./build-avr.sh ;;
*)            SCRIPT=./build-newlib.sh ;;
esac

echo | ${SCRIPT} ${PACKAGES}
