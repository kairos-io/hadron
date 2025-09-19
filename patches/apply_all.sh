#!/bin/bash
set -ex

PATCH_DIR=$1
SOURCE_DIR=$2
PATCH_FILES=${PATCH_FILES:-$(find $PATCH_DIR -name '*.patch' | sort -n)}

echo "Applying patches from $PATCH_DIR to $SOURCE_DIR"
echo "Patch files: $PATCH_FILES"

if [ -z "$PATCH_FILES" ]; then
    echo "No patch files found in $PATCH_DIR"
    exit 1
fi

pushd $SOURCE_DIR
    # Apply all patches in the patches directory
    for patch in $PATCH_FILES; do
        echo "Applying patch $patch"
        patch -p1 < $patch
    done
popd