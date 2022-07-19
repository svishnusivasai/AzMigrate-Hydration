#!/bin/bash
set -o errexit

export ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd  )"
cd $ROOT/../host

MajorVersion=`grep MajorVersion $ROOT/BuildConfig.bcf | cut -f 2 -d "="`
MinorVersion=`grep MinorVersion $ROOT/BuildConfig.bcf | cut -f 2 -d "="`
PatchsetVersion=`grep PatchsetVersion $ROOT/BuildConfig.bcf | cut -f 2 -d "="`
PatchVersion=`grep PatchVersion $ROOT/BuildConfig.bcf | cut -f 2 -d "="`
BuildQuality=`grep BuildQuality $ROOT/BuildConfig.bcf | cut -f 2 -d "="`
BuildPhase=`grep BuildPhase $ROOT/BuildConfig.bcf | cut -f 2 -d "="`

gmake AzureRecoveryUtil X_VERSION_MAJOR=$MajorVersion X_VERSION_MINOR=$MinorVersion X_PATCH_SET_VERSION=$PatchsetVersion X_PATCH_VERSION=$PatchVersion X_VERSION_QUALITY=$BuildQuality X_VERSION_PHASE=$BuildPhase debug=no warnlevel=none verbose=yes partner=inmage > >(tee AzureRecoveryUtilBuild.log) 2>&1

if [ $? -eq 0 ]; then
   echo "Build succeeded."
else
   echo "Build failed."
fi