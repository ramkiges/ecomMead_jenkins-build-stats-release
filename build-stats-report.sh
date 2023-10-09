#!/bin/sh
PATH=/apps/mead-tools:/opt/homebrew/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH

DAYS=31
REPORT_PCTL=80
REPORT_DEPTH=20
GROUP_LIST="vue- ecom- web- dp-"
EXCLUDE="wcm|aes|ecm|assortment-export-service|buildsystem|bgb|ecom-app-config|helm-config|akamai-manifest|k8s|catalog-.*-config"
JENKINS="https://ecombuild.wsgc.com/jenkins/job"
TMP=$(mktemp -d -t tmp.$(basename $0).XXX)
OLD=$(date --date "-$DAYS days" '+%Y%m%d%H%M%S')

DOC_SPACE="ES"
CCLIDIR="/apps/scripts/env_summary/atlassian-cli-3.2.0"

HTML() { echo "$*" >> $OUTFILE; }

BailOut() {
  [[ -n $1 ]] && echo "$(basename $0): $*"
  [[ -n $TMP && -e $TMP ]] && rm -rf $TMP
  exit 255   
}

cleanUp() {
{ set +x; } 2>/dev/null
  cd /tmp
  [[ -n $TMP ]] && rm -rf $TMP
}
trap cleanUp EXIT

git clone -q --depth 1 git@github.wsgc.com:eCommerce-Mead/jenkins-build-stats.git $TMP || BailOut "Unable to clone"
cd $TMP || BailOut "Unable to cd to $TMP"

CSV_DVO=build-stats_history-devops.csv
CSV_ALL=build-stats_history-allorgs.csv
CSV_BED=build-stats_history-bedrock.csv
CSV_PLT=build-stats_history-platform.csv
rm -f $CSV_ALL $CSV_BED $CSV_PLT $CSV_DVO *.html

# trim datafile
sort -u csv/build-stats_history-*.csv |
while read build
do
  t=$(awk -F, '{ print $2 }' <<< $build)
  [[ $t -lt $OLD ]] && continue
  [[ $build =~ eCommerce-DevOps ]] && { echo "$build" >> $CSV_DVO; continue; }
  [[ $build =~ eCommerce-Bedrock ]] && { echo "$build" >> $CSV_BED; continue; }
  [[ $build =~ Platform-Application ]] && { echo "$build" >> $CSV_PLT; continue; }
  echo "$build" >> $CSV_ALL 
done

# first, create a file with the average times for each build
for ORG in all eCommerce-Bedrock Platform-Application eCommerce-DevOps
do
  case $ORG in
    eCommerce-DevOps )
      CSV=$CSV_DVO
      METRICS=build-stats_metrics-devops.csv
    ;;

    eCommerce-Bedrock )
      CSV=$CSV_BED
      METRICS=build-stats_metrics-bedrock.csv
    ;;

    Platform-Application )
      CSV=$CSV_PLT
      METRICS=build-stats_metrics-platform.csv
    ;;

    * )
      CSV=$CSV_ALL
      METRICS=build-stats_metrics-allorgs.csv
    ;;
  esac

  BUILD_LIST=$(awk -F, '{ print $1 }' $CSV | egrep -vi "$EXCLUDE" | sort -u)

  for build in $BUILD_LIST
  do
    grep "$build,.*,succ" $CSV > buildlist.txt
    build_count=$(grep "$build,.*,succ" $CSV | wc -l)
    [[ $build_count -eq 0 ]] && continue
    build_times=$(grep "$build,.*,succ" $CSV | awk -F, '{ print $6 }')
    build_time_total=0
    pctl=$(datamash -t, perc:$REPORT_PCTL 6 < buildlist.txt)
    mean=$(datamash -t, mean 6 < buildlist.txt)

    # do we really need to capture the most recent build?
    #recent=$(grep "$build,.*,succ" $CSV | tail -1)
    #[[ -z $recent ]] && recent=$(grep "$build," $CSV | tail -1)
    rm -f buildlist.txt

    for b in $build_times
    do
      build_time_total=$(expr $build_time_total + $b)
    done
    build_time_avg=$(bc <<< "scale=4; $build_time_total/$build_count")
    build_time_avg=$(printf "%.0f" "$build_time_avg")

    day_list=$(grep "$build" $CSV | awk -F, '{ print $2 }' | cut -c 1-8)
    day_count=$(grep "$build," $CSV | awk -F, '{ print $2 }' | cut -c 1-8 | wc -l)
    dbc=0
    for d in $day_list
    do
      dc=$(grep "$build,$d" $CSV | awk -F, '{ print $2 }' | cut -c 1-8 | wc -l)
      dbc=$(expr $dbc + $dc)
    done
    abpd=$(bc <<< "scale=4; $dbc/$day_count")
    abpd=$(printf "%.1f" "$abpd")

    echo "$build,$build_time_avg,$abpd,$pctl,$mean" >> $METRICS.new
  done

  sort -u -t, -k2nr $METRICS.new > $METRICS
  rm -f $METRICS.new 
done

# create a report of the longest X number of builds
for ORG in all eCommerce-Bedrock Platform-Application
do
  case $ORG in
    eCommerce-Bedrock )
      PAGENAME="Jenkins Build Statistics - $ORG"
      CSV=$CSV_BED
      OUTFILE=job-stats-bedrock.html
      METRICS=build-stats_metrics-bedrock.csv
      XLINK="<li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+Non-Bedrock'>Jenkins Build Statistics - Non-Bedrock</a></li>
      <li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+Platform-Application'>Jenkins Build Statistics - Platform Application</a></li>"
    ;;

    Platform-Application )
      PAGENAME="Jenkins Build Statistics - $ORG"
      CSV=$CSV_PLT
      OUTFILE=job-stats-platform.html
      METRICS=build-stats_metrics-platform.csv
      XLINK="<li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+eCommerce-Bedrock'>Jenkins Build Statistics - eCommerce-Bedrock</a></li>
      <li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+Non-Bedrock'>Jenkins Build Statistics - Non-Bedrock</a></li>"
    ;;

    all ) 
      PAGENAME="Jenkins Build Statistics - Non-Bedrock"
      CSV=$CSV_ALL
      OUTFILE=job-stats-allorgs.html
      METRICS=build-stats_metrics-allorgs.csv
      XLINK="<li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+eCommerce-Bedrock'>Jenkins Build Statistics - eCommerce-Bedrock</a></li>
      <li><a href='https://confluence.wsgc.com/display/ES/Jenkins+Build+Statistics+-+Platform-Application'>Jenkins Build Statistics - Platform Application</a></li>"
    ;;
  esac

  START=$(awk -F, '{ print $2 }' $CSV | sort -n | head -1)
  START="${START:0:4}-${START:4:2}-${START:6:2}"
  END=$(awk -F, '{ print $2 }' $CSV | sort -n | tail -1)
  END="${END:0:4}-${END:4:2}-${END:6:2}"

  HTML "<p>Date range: $START - $END</p>
<p>This is a report detailing the $REPORT_DEPTH longest-running Jenkins jobs from the last $DAYS days, with one table representing all jobs, and separate tables for specific groups of jobs.  <a href='https://github.wsgc.com/eCommerce-Mead/jenkins-build-stats'>Github link</a></p>
<p><i>See also:</i> <ul>$XLINK</ul></p>"

  for grp in all $GROUP_LIST
  do
    [[ $grp = 'all' ]] && { grp=".*"; label="All Jobs"; } || label="$grp* Jobs"
    egrep -iq "$grp" $METRICS || continue

    HTML "<h4>$label</h4>"
    HTML "<table border='1' width='70%'>"
    HTML "<tr>"
    HTML "<th style='text-align:center'>Job</th>"
    #HTML "<th style='text-align:center'>Average Duration</th>"
    #HTML "<th style='text-align:center'>Mean</th>"
    HTML "<th style='text-align:center'>${REPORT_PCTL}th Percentile</th>"
    HTML "<th style='text-align:center'>Average Builds/Day</th>"
    HTML "</tr>"

    for line in $(egrep -i "$grp" $METRICS | sort -u -t, -k4nr | head -$REPORT_DEPTH)
    do
      job=$(awk -F, '{ print $1 }' <<< $line)
      branch=$(awk -F/ '{ print $3 }' <<< $job)
      org=$(awk -F/ '{ print $1 }' <<< $job)
      job=$(awk -F/ '{ print $2 }' <<< $job)
      link="$JENKINS/$org/job/$job/job/$branch/"

      avg_duration=$(awk -F, '{ print $2 }' <<< $line)
      avg_per_day=$(awk -F, '{ print $3 }' <<< $line)
      avg_duration=$(date -d@$(expr $avg_duration / 1000) -u +%H:%M:%S)

      pctl=$(awk -F, '{ print $4 }' <<< $line | awk -F\. '{ print $1 }')
      pctl=$(date -d@$(expr $pctl / 1000) -u +%H:%M:%S)

      mean=$(awk -F, '{ print $5 }' <<< $line | awk -F\. '{ print $1 }')
      mean=$(date -d@$(expr $mean / 1000) -u +%H:%M:%S)

      HTML "<tr>"
      HTML "  <td><a href='$link'>$org/$job/$branch</a></td>"
      HTML "  <!--<td style='text-align:right'>$avg_duration</td>-->"
      #HTML "  <td style='text-align:right'>$mean</td>"
      HTML "  <td style='text-align:right'>$pctl</td>"
      HTML "  <td style='text-align:right'>$avg_per_day</td>"
      HTML "</tr>"
    done
    HTML "</table>"
  done

  HTML "<p><font size='-1'>$(hostname) $0/$LOGNAME</font></p>"

  echo "*** Update confluence $PAGENAME $OUTFILE"
  sh $CCLIDIR/confluence.sh --space "$DOC_SPACE" --title "$PAGENAME" --action storepage --file $OUTFILE --noConvert --verbose || BailOut "Confluence update failed"

  set -x
  git add ${METRICS} ${CSV} 
  git pull -q --rebase >/dev/null 2>&1
  git commit -q -m "Update $ORG [trim]" >/dev/null 2>&1
  git push -q -f
  set +x
done

cd /tmp

exit 0

