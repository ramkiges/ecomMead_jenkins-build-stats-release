#!/bin/sh
PATH=/apps/mead-tools:/opt/homebrew/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH

ORG_EXCLUDE="b2bsite|whitney|tahoe|mead|Kubernetes|TestAutomation|Release-Management|Breads|Huron"
TMP=$(mktemp -d -t tmp.$(basename $0).XXX)

BailOut() {
  [[ -n $1 ]] && echo "$(basename $0): $*"
  exit 255   
}

cleanUp() {
{ set +x; } 2>/dev/null
  cd /tmp
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

git clone -q --depth 1 git@github.wsgc.com:eCommerce-Mead/jenkins-build-stats.git $TMP || BailOut "Unable to clone"
cd $TMP

ORG_LIST=$(curl -fskq https://ecombuild.wsgc.com/jenkins/view/all/ | \
  grep '<a href="job/.*/"' | \
  awk -F 'href=' '{ print $2 }'| \
  awk '{ print $1 }' | \
  awk -F/ '{ print $2 }' | \
  grep "eCommerce-" | \
  egrep -vi "$ORG_EXCLUDE|eCommerce-Bedrock|Platform-Application" | \
  sort -u )

renice -n +20 $$
date
for org in eCommerce-Bedrock Platform-Application $ORG_LIST
do  
  echo "org: $org"
  date > /tmp/$org.out
  ./build-stats-fetch.sh $org >> /tmp/$org.out 2>&1 &
done
wait
date

./build-stats-report.sh

exit 0
