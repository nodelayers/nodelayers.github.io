PACKAGE_NAME=${1}
LAYER_NAME=${2:-$1}
echo "PACKAGE_NAME=${PACKAGE_NAME}"
echo "LAYER_NAME=${LAYER_NAME}"
LAYER_TMP=$(mktemp -d)
BASE_DIR=$(pwd)

pushd ${LAYER_TMP}

mkdir -p nodejs/node_modules
pushd nodejs/node_modules
npm install -save false --global-style ${PACKAGE_NAME}
pushd ${PACKAGE_NAME}
PACKAGE_VERSION=$(jq -r .version package.json)
PACKAGE_DESCRIPTION=$(jq -r .description package.json)
PACKAGE_LICENSE=$(jq -r .license package.json)
PACKAGE_JSON=$(jq -cM '{description,keywords,license,version}' package.json)
popd
popd
zip -r layer.zip nodejs

echo $PACKAGE_JSON
INPUT=$(cat "${BASE_DIR}/layers.json")
echo ${INPUT} | jq -M ".\"${PACKAGE_NAME}\" = ${PACKAGE_JSON}" > "${BASE_DIR}/layers.json"

publish_layer () {
    LAYER_DESCRIPTION="${PACKAGE_NAME}@${PACKAGE_VERSION}"
    PUBLISH_RESULT=$(AWS_REGION="${1}" aws lambda publish-layer-version --layer-name "${LAYER_NAME}" --description "${LAYER_DESCRIPTION}" --license-info "${PACKAGE_LICENSE}" --zip-file "fileb://layer.zip")
    LAYER_VERSION=$(jq -r .Version <<< "${PUBLISH_RESULT}")
    LAYER_VERSION_ARN=$(jq -r .LayerVersionArn <<< "${PUBLISH_RESULT}")
    AWS_REGION=${1} aws lambda add-layer-version-permission --layer-name "${LAYER_NAME}" --version-number "${LAYER_VERSION}" --statement-id "GetLayerVersion" --action "lambda:GetLayerVersion" --principal "*" 

    INPUT=$(cat "${BASE_DIR}/layers.json")
    echo ${INPUT} | jq -M ".\"${PACKAGE_NAME}\"._regions.\"${1}\" = \"${LAYER_VERSION_ARN}\"" > "${BASE_DIR}/layers.json"

    # jq -M ".\"${PACKAGE_NAME}\".\"${PACKAGE_VERSION}\".\"${1}\" = \"${LAYER_VERSION_ARN}\"" "${BASE_DIR}/layer-versions.json" > "${BASE_DIR}/layer-versions.json"
}

AWS_REGIONS=('us-east-1' 'us-east-2' 'us-west-1' 'us-west-2' 'eu-west-1' 'eu-west-2' 'eu-central-1')
for region in "${AWS_REGIONS[@]}"
do
  publish_layer $region
done

popd

rm -rf ${LAYER_TMP}
