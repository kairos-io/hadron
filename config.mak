# NATIVE = 1
# TARGET = x86_64-linux-musl

# TARGET := x86_64-ukairos-linux-musl

# Re-enable when native build works (see build.yaml)
# https://github.com/richfelker/musl-cross-make/issues/98
ifneq ($(NATIVE),)
	OUTPUT := /musl
	# stackoverflow.com/a/324782
	TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
	PATH := $(TOP)/output/bin:$(TOP)/output/$(TARGET)/bin:$(PATH)
endif

# DL_CMD = curl -Lo

COMMON_CONFIG += CC='cc'
COMMON_CONFIG += CXX='c++'

COMMON_CONFIG += CFLAGS='-O2 -pipe'
COMMON_CONFIG += CXXFLAGS='-O2 -pipe'
COMMON_CONFIG += LDFLAGS='-s'

COMMON_CONFIG += --with-build-sysroot=/
COMMON_CONFIG += --disable-nls
#COMMON_CONFIG += --prefix=/usr
COMMON_CONFIG += --enable-deterministic-archives
#COMMON_CONFIG += --with-debug-prefix-map=$(CURDIR)=

# https://github.com/richfelker/musl-cross-make/issues/97
GCC_CONFIG += --disable-multiarch

GCC_CONFIG += --with-native-system-header-dir=/usr/include
GCC_CONFIG += --disable-bootstrap
GCC_CONFIG += --disable-libgomp
GCC_CONFIG += --disable-libquadmath
GCC_CONFIG += --disable-lto
# Enable -fPIC so to build shared libs as well.
# See https://github.com/richfelker/musl-cross-make/issues/47
# e.g. https://github.com/rust-lang/rust/pull/59468/files
#GCC_CONFIG += --enable-default-pie
#GCC_CONFIG += --enable-languages=c,c++,go
#GCC_CONFIG += --bindir=/usr/bin
GCC_CONFIG += --prefix=/usr
#GCC_CONFIG += --with-local-prefix=/usr/include

KERNEL_VARS += HOSTCC='cc'

# only static
#COMMON_CONFIG += --disable-shared
#MUSL_CONFIG += --disable-shared

# COMMON_CONFIG += CC='cc -static --static'
# COMMON_CONFIG += CXX='c++ -static --static'

# KERNEL_VARS += HOSTCC='cc -static'