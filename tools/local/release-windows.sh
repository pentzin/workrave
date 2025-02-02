#!/bin/bash -ex

init() {
    if [ ! -d "${WORKSPACE}" ]; then
        mkdir -p "${WORKSPACE}"
    fi

    cd $WORKSPACE

    if [ ! -d ${SOURCES_DIR}/.git ]; then
        mkdir -p ${SOURCES_DIR}
        git clone $REPO source
        cd source
        git checkout $COMMIT
    else
        cd source
        git fetch
        git checkout $COMMIT

    fi

    cd $SOURCES_DIR

    if [ -n "$WORKRAVE_OVERRIDE_GIT_VERSION" ]; then
        GIT_VERSION=$WORKRAVE_OVERRIDE_GIT_VERSION
        GIT_TAG=$WORKRAVE_OVERRIDE_GIT_VERSION
    else
        GIT_TAG=$(git describe --abbrev=0)
        GIT_VERSION=$(git describe --tags --abbrev=10 2>/dev/null | sed -e 's/-g.*//')
        VERSION=$(echo $GIT_VERSION | sed -e 's/_/./g' | sed -e 's/-.*//g')
    fi

    if [ $GIT_VERSION = $GIT_TAG ]; then
        echo "Release build"
        export WORKRAVE_RELEASE_TAG=$GIT_TAG
    else
        echo "Snapshot build ($GIT_VERSION) of release ($GIT_TAG)"
    fi
}

setup() {
    cd $WORKSPACE/source
    rm -rf _build _deploy _output
    git reset --hard HEAD
    git clean -fdx
    git checkout $COMMIT
}

usage() {
    echo "Usage: $0 " 1>&2
    exit 1
}

parse_arguments() {
    while getopts "C:dPr:R:S:st:W:" o; do
        case "${o}" in
        C)
            SCRIPTS_DIR="${OPTARG}"
            ;;
        d)
            DRYRUN=-d
            ;;
        P)
            PRERELEASE=1
            ;;
        r)
            export WORKRAVE_OVERRIDE_GIT_VERSION="${OPTARG}"
            ;;
        R)
            REPO="${OPTARG}"
            ;;
        s)
            DOSIGN=1
            ;;
        S)
            SECRETS_DIR="${OPTARG}"
            ;;
        t)
            COMMIT="${OPTARG}"
            ;;
        W)
            WORKSPACE="${OPTARG}"
            ;;
        *)
            usage
            ;;
        esac
    done
    shift $((OPTIND - 1))
}

upload() {
    "${AWS}" configure set aws_access_key_id travis
    "${AWS}" configure set aws_secret_access_key ${SNAPSHOTS_SECRET_ACCESS_KEY}
    "${AWS}" configure set default.region us-east-1
    "${AWS}" configure set default.s3.signature_version s3v4
    "${AWS}" configure set s3.endpoint_url https://snapshots.workrave.org/
    "${AWS}" s3 --endpoint-url https://snapshots.workrave.org/ cp --recursive ${ARTIFACTS} s3://snapshots/v1.11
}

export WORKRAVE_ENV=local-windows-msys2

export WORKSPACE=$(pwd)/_workrave_build_workspace
export SCRIPTS_DIR=${WORKSPACE}/source/tools/
export SECRETS_DIR=

export DOSIGN=
export PRERELEASE=
export WORKRAVE_OVERRIDE_GIT_VERSION=
export REPO=https://github.com/rcaelers/workrave.git
export DRYRUN=

parse_arguments $*

export SOURCES_DIR=${WORKSPACE}/source
mkdir -p ${SOURCES_DIR}

# WORKRAVE_BUILD_DATETIME: ${{ needs.prep.outputs.WORKRAVE_BUILD_DATETIME }}
# WORKRAVE_BUILD_DATE: ${{ needs.prep.outputs.WORKRAVE_BUILD_DATE }}

if [ -z ${SECRETS_DIR} ]; then
    echo No secrets directory specified.
    exit 1
fi

BASEDIR=$(dirname "$0")
source ${BASEDIR}/../ci/config.sh

source ${SECRETS_DIR}/env-snapshots

init
setup

export OPENSSL=${OPENSSL:-"/opt/openssl/bin/openssl"}
export AWS=${AWS:-"/c/Program Files/Amazon/AWSCLIV2/aws"}

if [ -n "$DOSIGN" ]; then
    export SIGNTOOL="c:\Program Files (x86)\Windows Kits\10\bin\10.0.22000.0\x64\signtool.exe"
    export SIGNTOOL_SIGN_ARGS="/n Rob /t http://time.certum.pl /fd sha256 /v"
fi

export PATH="/c/Program Files/nodejs":$PATH
export WORKRAVE_JOB_INDEX=0
$SCRIPTS_DIR/ci/catalog.sh

export CONF_CONFIGURATION=Release
export WORKRAVE_JOB_INDEX=1
# export CONF_ENABLE="TESTS, CRASHPAD, AUTO_UPDATE"
export CONF_ENABLE="TESTS"
$SCRIPTS_DIR/ci/build.sh

export CONF_CONFIGURATION=Debug
export WORKRAVE_JOB_INDEX=2
# export CONF_ENABLE="TESTS, CRASHPAD, AUTO_UPDATE"
export CONF_ENABLE="TESTS"
$SCRIPTS_DIR/ci/build.sh

export ARTIFACTS=${SOURCES_DIR}/_deploy
${SCRIPTS_DIR}/ci/sign.sh

if [ -z "${DRYRUN}" ]; then
    upload
fi
