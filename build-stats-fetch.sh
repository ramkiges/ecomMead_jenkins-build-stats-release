#!/bin/sh
PATH=/apps/mead-tools:/opt/homebrew/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH

DAYS=31
export DEPTH=15
REPO=git@github.wsgc.com:eCommerce-Mead/jenkins-build-stats.git
PROJECT_EXCLUDE="wcm|aes|ecm|assortment-export-service|buildsystem|bgb|ecom-app-config|helm-config|akamai-manifest|k8s|catalog-.*-config|service-.*-config|dp-end2end|env-manifest|hinoki|evergreen-core"
JENKINS="https://ecombuild.wsgc.com/jenkins/job"
TIMEOUT="--retry 3 --max-time 30 --connect-timeout 45 --retry-delay 15"
OLD=$(date --date "-$DAYS days" '+%Y%m%d%H%M%S')
TMP=$(mktemp -d -t tmp.$(basename $0).XXX)

BailOut() {
  [[ -n $1 ]] && echo "$(basename $0): $*"
  exit 1
}

cleanUp() {
{ set +x; } 2>/dev/null
  cd /tmp
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

[[ -n $1 ]] && ORG_LIST=$* || ORG_LIST="eCommerce-Bedrock Platform-Application"

renice -n +20 $$

git clone -q --depth 1 $REPO $TMP || BailOut "Unable to clone $REPO"
cd $TMP || BailOut "Unable to cd to $TMP"

for ORG in $ORG_LIST
do
  ORG=$(sed -es/\.csv//gi -es/build-stats_history-//gi <<< $ORG)
  HISTORY=csv/build-stats_history-$ORG.csv
  [[ -e $HISTORY ]] || touch $HISTORY

  for project in $(curl $TIMEOUT -fskq $JENKINS/$ORG/ |
    grep '<a href="job/.*/"' | awk -F 'href=' '{ print $2 }'| awk '{ print $1 }' | awk -F/ '{ print $2 }' | egrep -iv "$PROJECT_EXCLUDE" | sort -u)
  do
    if [[ $ORG =~ Bedrock ]]
    then
      SLEEP=2
    else  
      SLEEP=$(ps -ef | grep "$(basename $0)" | egrep -iv "grep" | wc -l)
      SLEEP=$(expr $SLEEP / 4)
      [[ $SLEEP -lt 2 ]] && SLEEP=2
    fi

    for branch in $(curl $TIMEOUT -fsqk $JENKINS/$ORG/job/$project/ | 
      grep '<a href="job/.*/"' | awk -F 'href=' '{ print $2 }'| awk '{ print $1 }' | awk -F/ '{ print $2 }' | sort -u)
    do
      get-job-history $JENKINS/$ORG/job/$project/job/$branch >> ${HISTORY} &
      sleep $SLEEP >/dev/null 2>&1
    done # branch
  done # project

  # trim datafile
  rm -f ${HISTORY}.new
  sort -u ${HISTORY} | 
  while read build
  do
    t=$(awk -F, '{ print $2 }' <<< $build)
    [[ $t -lt $OLD ]] && continue
    echo "$build" >> ${HISTORY}.new
  done
  mv ${HISTORY}.new ${HISTORY}

  set -x
  git stash -q
  git pull -q --rebase
  git stash pop -q

  git add csv
  git add $HISTORY
  git commit -q -m "Update $ORG [trim]" #>/dev/null 2>&1
  git push -q -f
  { set +x; } 2>/dev/null 

  git status
done # org

echo "$ORG complete"

exit 0
