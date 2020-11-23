#!/bin/sh

g++ bindings.cpp -I../annoy/src \
    -std=c++14 \
    -D_CRT_SECURE_NO_WARNINGS \
    -march=native \
    -O3 -ffast-math -fno-associative-math \
    -shared -fPIC \
    -DANNOYLIB_MULTITHREADED_BUILD \
    -o libannoy.so \

$ACL_HOME/mlisp -q -L $AGRAPH_CLIENT -C "wf_patch.lisp" --kill

export DIST="wf_patch"

mkdir -p $DIST

cp libannoy.so wf_patch.fasl $DIST/

pandoc -s README.md -t html -o $DIST/doc.html

tar czvf $DIST.tar.gz $DIST
