#!/usr/bin/env bash

source script/init.sh

case $TARGET in
*-msdosdjgpp) ;;
*) TARGET="i686-pc-msdosdjgpp" ;;
esac

#DJGPP_DOWNLOAD_BASE="ftp://ftp.delorie.com/pub"
export DJGPP_DOWNLOAD_BASE="http://www.delorie.com/pub"

prepend BINUTILS_CONFIGURE_OPTIONS "--disable-werror
                                    --disable-nls"

prepend GCC_CONFIGURE_OPTIONS "--disable-nls
                               --enable-libquadmath-support
                               --enable-version-specific-runtime-libs
                               --enable-fat"

prepend GDB_CONFIGURE_OPTIONS "--disable-werror
                               --disable-nls
                               --with-system-readline"

if [ -z $1 ]; then
  echo "Usage: $0 [packages...]"
  echo "Supported packages:"
  ls djgpp/
  ls common/
  exit 1
fi

while [ ! -z $1 ]; do
  if [ ! -x djgpp/$1 ] && [ ! -x common/$1 ]; then
    echo "Unsupported package: $1"
    exit 1
  fi

  [ -e djgpp/$1 ] && source djgpp/$1 || source common/$1
  shift
done

DEPS=""

if [ -z ${IGNORE_DEPENDENCIES} ]; then
  [ ! -z ${GCC_VERSION} ] && DEPS+=" djgpp binutils"
  [ ! -z ${BINUTILS_VERSION} ] && DEPS+=" "
  [ ! -z ${GDB_VERSION} ] && DEPS+=" "
  [ ! -z ${DJGPP_VERSION} ] && DEPS+=" "
  [ ! -z ${BUILD_DXEGEN} ] && DEPS+=" djgpp binutils gcc"
  
  for DEP in ${DEPS}; do
    case $DEP in
      djgpp)
        [ -z ${DJGPP_VERSION} ] \
          && source djgpp/djgpp
        ;;
      binutils)
        [ -z "`ls ${PREFIX}/${TARGET}/etc/binutils-*-installed 2> /dev/null`" ] \
          && [ -z ${BINUTILS_VERSION} ] \
          && source djgpp/binutils
        ;;
      gcc)
        [ -z "`ls ${PREFIX}/${TARGET}/etc/gcc-*-installed 2> /dev/null`" ] \
          && [ -z ${GCC_VERSION} ] \
          && source common/gcc
        ;;
      gdb)
        [ -z "`ls ${PREFIX}/${TARGET}/etc/gdb-*-installed 2> /dev/null`" ] \
          && [ -z ${GDB_VERSION} ] \
          && source common/gdb
        ;;
      dxegen)
        [ -z "`ls ${PREFIX}/${TARGET}/etc/dxegen-installed 2> /dev/null`" ] \
          && [ -z ${BUILD_DXEGEN} ] \
          && source djgpp/dxegen
        ;;
    esac
  done
fi

if [ ! -z ${GCC_VERSION} ]; then
  DJCROSS_GCC_ARCHIVE="http://ap1.pp.fi/djgpp/gcc/${GCC_VERSION}/rpm/djcross-gcc-${GCC_VERSION}.tar.bz2"
  # djcross-gcc-X.XX-tar.* maybe moved from /djgpp/rpms/ to /djgpp/deleted/rpms/ directory.
  OLD_DJCROSS_GCC_ARCHIVE=${DJCROSS_GCC_ARCHIVE/rpms\//deleted\/rpms\/}
fi

source ${BASE}/script/download.sh

source ${BASE}/script/build-tools.sh

cd ${BASE}/build/ || exit 1

if [ ! -z ${BINUTILS_VERSION} ]; then
  echo "Building binutils"
  mkdir -p bnu${BINUTILS_VERSION}s
  cd bnu${BINUTILS_VERSION}s
  if [ ! -e binutils-unpacked ]; then
    unzip -o ../../download/bnu${BINUTILS_VERSION}s.zip || exit 1

    # patch for binutils 2.27
    [ ${BINUTILS_VERSION} == 227 ] && (patch gnu/binutils-*/bfd/init.c ${BASE}/patch/patch-bnu27-bfd-init.txt || exit 1 )

    touch binutils-unpacked
  fi
  cd gnu/binutils-* || exit 1

  # exec permission of some files are not set, fix it.
  for EXEC_FILE in install-sh missing configure; do
    echo "chmod a+x $EXEC_FILE"
    chmod a+x $EXEC_FILE || exit 1
  done

  source ${BASE}/script/build-binutils.sh
fi

cd ${BASE}/build/ || exit 1

if [ ! -z ${DJGPP_VERSION} ] || [ ! -z ${BUILD_DXEGEN} ]; then
  echo "Prepare djgpp"
  rm -rf ${BASE}/build/djgpp-${DJGPP_VERSION}
  mkdir -p ${BASE}/build/djgpp-${DJGPP_VERSION}
  cd ${BASE}/build/djgpp-${DJGPP_VERSION} || exit 1
  unzip -o ../../download/djdev${DJGPP_VERSION}.zip || exit 1
  unzip -o ../../download/djlsr${DJGPP_VERSION}.zip || exit 1
  unzip -o ../../download/djcrx${DJGPP_VERSION}.zip || exit 1
  patch -p1 -u < ../../patch/patch-djlsr${DJGPP_VERSION}.txt || exit 1
  patch -p1 -u < ../../patch/patch-djcrx${DJGPP_VERSION}.txt || exit 1

  cd src/stub
  ${CC} -O2 ${CFLAGS} stubify.c -o stubify || exit 1
  ${CC} -O2 ${CFLAGS} stubedit.c -o stubedit || exit 1
  ${HOST_CC} -O2 ${CFLAGS} stubify.c -o ${TARGET}-stubify || exit 1
  ${HOST_CC} -O2 ${CFLAGS} stubedit.c -o ${TARGET}-stubedit || exit 1

  cd ../..

  ${SUDO} mkdir -p $PREFIX/${TARGET}/sys-include || exit 1
  ${SUDO} cp -rp include/* $PREFIX/${TARGET}/sys-include/ || exit 1
  ${SUDO} cp -rp lib $PREFIX/${TARGET}/ || exit 1
  ${SUDO} mkdir -p $PREFIX/bin || exit 1
  ${SUDO} cp -p src/stub/${TARGET}-stubify $PREFIX/bin/ || exit 1
  ${SUDO} cp -p src/stub/${TARGET}-stubedit $PREFIX/bin/ || exit 1

  ${SUDO} rm ${PREFIX}/${TARGET}/etc/djgpp-*-installed
  ${SUDO} touch ${PREFIX}/${TARGET}/etc/djgpp-${DJGPP_VERSION}-installed
fi

cd ${BASE}/build/

if [ ! -z ${GCC_VERSION} ]; then
  # build gcc
  untar djcross-gcc-${GCC_VERSION} || exit 1
  cd djcross-gcc-${GCC_VERSION}/

  BUILDDIR=`pwd`
  export PATH="${BUILDDIR}/tmpinst/bin:$PATH"

  if [ ! -e ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built ]; then
    echo "Building autoconf"
    cd $BUILDDIR
    untar autoconf-${AUTOCONF_VERSION} || exit 1
    cd autoconf-${AUTOCONF_VERSION}/
      ./configure --prefix=$BUILDDIR/tmpinst || exit 1
      ${MAKE} -j${MAKE_JOBS} all install || exit 1
    rm ${BUILDDIR}/tmpinst/autoconf-*-built
    touch ${BUILDDIR}/tmpinst/autoconf-${AUTOCONF_VERSION}-built
  else
    echo "autoconf already built, skipping."
  fi

  if [ ! -e ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built ]; then
    echo "Building automake"
    cd $BUILDDIR
    untar automake-${AUTOMAKE_VERSION} || exit 1
    cd automake-${AUTOMAKE_VERSION}/
    ./configure --prefix=$BUILDDIR/tmpinst || exit 1
      ${MAKE} all install || exit 1
    rm ${BUILDDIR}/tmpinst/automake-*-built
    touch ${BUILDDIR}/tmpinst/automake-${AUTOMAKE_VERSION}-built
  else
    echo "automake already built, skipping."
  fi

  cd $BUILDDIR

  if [ ! -e gcc-unpacked ]; then
    echo "Patch unpack-gcc.sh"

    if [ `uname` = "FreeBSD" ]; then
      # The --verbose option is not recognized by BSD patch
      sed -i 's/patch --verbose/patch/' unpack-gcc.sh || exit 1
    fi

    echo "Running unpack-gcc.sh"
    sh unpack-gcc.sh --no-djgpp-source $(ls -t ../../download/gcc-${GCC_VERSION}.tar.* | head -n 1) || exit 1

    # patch gnu/gcc-X.XX/gcc/doc/gcc.texi
    echo "Patch gcc/doc/gcc.texi"
    cd gnu/gcc-*/gcc/doc || exit 1
    sed -i "s/[^^]@\(\(tex\)\|\(end\)\)/\n@\1/g" gcc.texi || exit 1
    cd -

    # copy stubify programs
    cp -p ${BASE}/build/djgpp-${DJGPP_VERSION}/src/stub/stubify $BUILDDIR/tmpinst/bin/

    cd $BUILDDIR/

    # download mpc/gmp/mpfr/isl libraries
    echo "Downloading gcc dependencies"
    cd gnu/gcc-${GCC_VERSION_SHORT}
    ./contrib/download_prerequisites

    # apply extra patches if necessary
    [ -e ${BASE}/patch/patch-djgpp-gcc-${GCC_VERSION}.txt ] && patch -p 1 -u -i ${BASE}/patch/patch-djgpp-gcc-${GCC_VERSION}.txt
    cd -

    touch gcc-unpacked
  else
    echo "gcc already unpacked, skipping."
  fi

  echo "Building gcc"

  mkdir -p djcross
  cd djcross || exit 1

  TEMP_CFLAGS="$CFLAGS"
  export CFLAGS="$CFLAGS $GCC_EXTRA_CFLAGS"
  
  GCC_CONFIGURE_OPTIONS+=" --target=${TARGET} --prefix=${PREFIX} ${HOST_FLAG} ${BUILD_FLAG}
                           --enable-languages=${ENABLE_LANGUAGES}"
  strip_whitespace GCC_CONFIGURE_OPTIONS

  if [ ! -e configure-prefix ] || [ ! "`cat configure-prefix`" == "${GCC_CONFIGURE_OPTIONS}" ]; then
    rm -rf *
    ../gnu/gcc-${GCC_VERSION_SHORT}/configure ${GCC_CONFIGURE_OPTIONS} || exit 1
    echo ${GCC_CONFIGURE_OPTIONS} > configure-prefix
  else
    echo "Note: gcc already configured. To force a rebuild, use: rm -rf $(pwd)"
    sleep 5
  fi

  ${MAKE} -j${MAKE_JOBS} || exit 1
  [ ! -z $MAKE_CHECK_GCC ] && ${MAKE} -j${MAKE_JOBS} -s check-gcc | tee ${BASE}/tests/gcc.log
  ${SUDO} ${MAKE} -j${MAKE_JOBS} install-strip || exit 1
  ${SUDO} ${MAKE} -j${MAKE_JOBS} -C mpfr install

  rm ${PREFIX}/${TARGET}/etc/gcc-*-installed
  touch ${PREFIX}/${TARGET}/etc/gcc-${GCC_VERSION}-installed

  export CFLAGS="$TEMP_CFLAGS"
fi

# gcc done

if [ ! -z ${DJGPP_VERSION} ]; then
  # build djlsr (for dxegen / exe2coff)
  cd ${BASE}/build/djgpp-${DJGPP_VERSION}
  if [ "$CC" == "gcc" ] && [ ! -z ${BUILD_DXEGEN} ]; then
    echo "Building DXE tools."
    cd src
    PATH=$PREFIX/bin/:$PATH ${MAKE} || exit 1
    cd dxe
    ${SUDO} cp -p dxegen  $PREFIX/bin/${TARGET}-dxegen || exit 1
    ${SUDO} cp -p dxe3gen $PREFIX/bin/${TARGET}-dxe3gen || exit 1
    ${SUDO} cp -p dxe3res $PREFIX/bin/${TARGET}-dxe3res || exit 1
    cd ../..
    touch ${PREFIX}/${TARGET}/etc/dxegen-installed
  else
    echo "Building DXE tools requires gcc, skip."
  fi
  cd src/stub
  ${HOST_CC} -O2 ${CFLAGS} -o exe2coff exe2coff.c || exit 1
  ${SUDO} cp -p exe2coff $PREFIX/bin/${TARGET}-exe2coff || exit 1

  # djlsr done
fi

cd ${BASE}/build

source ${BASE}/script/build-gdb.sh

source ${BASE}/script/finalize.sh
