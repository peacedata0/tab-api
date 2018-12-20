#!/bin/bash

: <<'_SCRIPT_DOCUMENTATION_'
INFORMATION
Project : Tableau reporting (internal)
Purpose : Fetch data via tableau api, prep via jq
Inputs  : tableau api
Outputs : schedules.tsv, sites*.tsv

# PROCESS OVERVIEW
Compile listing of published views by site and make note of
project, workbook, owner, & relevant dates.

# ROADMAP
get project & workbook urls if possible to reverse-engineer the
sequencing tableau uses.

# CHANGELOG

## v1.1.0 - 2018-12-20 - RK
added sites-datasources-revisions, sites-workbooks-revisions, & sites-favorites

## v1.0.1 - 2018-12-19 - RK
added siteurl (contentUrl) to outputs to enable creating complete links
changed output to be more specific about which server and site is currently being queried

## v1.0.0 - 2018-12-13 - RK
Initial version

_SCRIPT_DOCUMENTATION_

page_size=1000		# 1-1000. api limit.

if [ ! -d "output" ]
then
	mkdir output
fi
cd output/

function clean(){
	rm *.json
	for f in schedules serverinfo sites-datasources sites-datasources-revisions sites-groups-users sites-favorites sites-groups sites-projects sites-subscriptions sites-tasks-extractRefreshes sites-users-workbooks sites-users sites-views sites-workbooks sites-workbooks-revisions sites
	do
		[ -f ${f}.tsv ] && rm ${f}.tsv
		[ -f _${f}.tsv ] && mv _${f}.tsv ${f}.tsv
	done
}

function appendData(){
	if [ ! -f _${1} ]
	then
		cp ${1} _${1}
	else
		tail -n+2 ${1} >> _${1}
	fi
}

function auth(){
#	echo "${FUNCNAME[0]} ${1}"
	local t=''
	if [ "${1}" == "signin" ]
	then
		t="-d @req.json"
	elif [ "${1}" == "switchSite" ]
	then
		jq -nc --arg u "${2}" '.site.contentUrl=$u' > req.json
		t="-H ${TOKEN} -d @req.json"
	else
		t="-H ${TOKEN}"
	fi
	curl --silent -X POST --url "${api_url}/auth/${1}" -H "Content-type:application/json" -H "Accept:application/json" ${t} --out auth.json
	if [ "${1}" != "signout" ]
	then
		TOKEN="X-Tableau-Auth:$(jq ".credentials.token" auth.json | cut -f 2 -d\")"
		SITEID=$(jq ".credentials.site.id" auth.json | cut -f 2 -d\")
		SITEURL=$(jq ".credentials.site.contentUrl" auth.json | cut -f2 -d\")
	fi
}

function getData(){ # getData endpoint .json.root .list,.of,.json.nodes.to.keep optional_constant_name optional_constant_value
#	echo "${FUNCNAME[0]}"
	local URL=${api_url}/$1
	# remove tableau id patterns (ef35fd3a-becb-4dfd-b2f1-9a076cf36424) to get a friendly filename
	fileout=$(echo "${1}" | sed -E "s/\/.{8}-.{4}-.{4}-.{4}-.{12}//g" | sed 's/\//-/g')
	local current_page=0
	local total_pages=1
	local total_count=0
	local JQ_FILTER=${3//_X_/\$_}
	echo ${JQ_FILTER//./} | tr ',' '\t' | tr -d '[$]' > ${fileout}.tsv # strip '.[]' and convert csv to tsv
	until [ ${current_page} -eq ${total_pages} ]
	do
		current_page=$((current_page+1))
		curl -s -X GET -H ${TOKEN} -H "Accept:application/json" --url "${URL}?fields=_all_&pageSize=${page_size}&pageNumber=${current_page}" --out ${fileout}.json

		# if the api returns an error, stop and alert
		if [ "$(jq -r '.error.code' ${fileout}.json)" != "null" ]
		then
			echo "egad! something has gone awry..."
			echo "URL: ${URL}"
			echo "JQ Filter: ${JQ_FILTER}"
			echo "json content:"
			jq '.' ${fileout}.json
			exit
		fi

		# if the passed root of the json has no length, break and keep quite
		if [ $(jq -r "${2%%[]} | length" ${fileout}.json) == "0" ]
		then
			continue
		fi

		# if the returned json has pagination node, get .pagination.totalAvailable
		if [ $(jq -r ".pagination | length" ${fileout}.json) != "0" ]
		then
			total_count=$(jq -r '.pagination.totalAvailable' ${fileout}.json)
		fi
		
		if [ ${total_count} != "null" ] && [ ${total_count} -gt 0 ] || [ "${fileout}" == "serverinfo" ] || [ "${fileout}" == "sites-favorites" ] || [ "${fileout}" == "sites-tasks-extractRefreshes" ]
		then
			jq -r --argjson _ "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\",\"groupid\":\"${GROUPID}\",\"userid\":\"${USERID}\",\"datasourceid\":\"${DATASOURCEID}\",\"workbookid\":\"${WORKBOOKID}\"}" "$2 | [ ${JQ_FILTER} ] | @tsv" ${fileout}.json >> ${fileout}.tsv
			total_pages=$(( ${total_count} / ${page_size} + 1 ))
			appendData ${fileout}.tsv
		fi
		echo "${server} - ${SITEURL} - ${fileout} - N=${total_count} - batch ${current_page} of ${total_pages}"
	done
}

function getServerData(){
	getData serverinfo .serverInfo _X_.serverurl,_X_.server,.productVersion.value,.productVersion.build,.restApiVersion
	getData sites .sites.site[] _X_.serverurl,_X_.server,.id,.name,.contentUrl,.adminMode,.state,.revisionHistoryEnabled,.subscribeOthersEnabled,.guestAccessEnabled,.cacheWarmupEnabled,.commentingEnabled
	getData schedules .schedules.schedule[] _X_.serverurl,_X_.server,.id,.name,.state,.priority,.createdAt,.updatedAt,.type,.frequency,.nextRunAt
}

function getSiteData(){
getData sites/${SITEID}/subscriptions .subscriptions.subscription[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.subject,.content.id,.content.type,.schedule.id,.schedule.name,.user.id,.user.name
getData sites/${SITEID}/tasks/extractRefreshes .tasks.task[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.extractRefresh.id,.extractRefresh.priority,.extractRefresh.consecutiveFailedCount,.extractRefresh.type,.extractRefresh.schedule.id,.extractRefresh.schedule.name,.extractRefresh.schedule.state,.extractRefresh.schedule.priority,.extractRefresh.schedule.createdAt,.extractRefresh.schedule.updatedAt,.extractRefresh.schedule.type,.extractRefresh.schedule.frequency,.extractRefresh.schedule.nextRunAt,.extractRefresh.workbook.id

getData sites/${SITEID}/datasources .datasources.datasource[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.type,.createdAt,.updatedAt,.isCertified,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin

# loop over all datasources to get revisions
if [ $(grep -v id sites-datasources.tsv | wc -l | awk '{print $1}') != "0" ]
then
	while IFS=',' read DATASOURCEID
	do
		getData sites/${SITEID}/datasources/${DATASOURCEID}/revisions .revisions.revision[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.datasourceid,.revisionNumber,.publishedAt,.deleted,.current,.sizeInBytes,.publisher.id,.publisher.name
	done << END_USER_LOOP
$(csvcut -t -c id sites-datasources.tsv | grep -v id)
END_USER_LOOP
fi

getData sites/${SITEID}/projects .projects.project[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.description,.contentPermissions
getData sites/${SITEID}/workbooks .workbooks.workbook[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin

# loop over all workbooks to get revisions
if [ $(grep -v id sites-workbooks.tsv | wc -l | awk '{print $1}') != "0" ]
then
	while IFS=',' read WORKBOOKID
	do
		getData sites/${SITEID}/workbooks/${WORKBOOKID}/revisions .revisions.revision[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.workbookid,.revisionNumber,.publishedAt,.deleted,.current,.sizeInBytes,.publisher.id,.publisher.name
	done << END_USER_LOOP
$(csvcut -t -c id sites-workbooks.tsv | grep -v id)
END_USER_LOOP
fi

getData sites/${SITEID}/views .views.view[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.createdAt,.updatedAt,.workbook.id,.workbook.name,.workbook.contentUrl,.workbook.showTabs,.workbook.size,.workbook.createdAt,.workbook.updatedAt,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin,.project.id,.project.name,.project.description,.usage.totalViewCount
getData sites/${SITEID}/groups .groups.group[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.domain.name

# loop over all groups to get user list
if [ $(grep -v id sites-groups.tsv | wc -l | awk '{print $1}') != "0" ]
then
	while IFS=',' read GROUPID
	do
		getData sites/${SITEID}/groups/${GROUPID}/users .users.user[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.groupid,.id,.name,.fullName,.email,.siteRole,.lastLogin
	done << END_GROUP_LOOP
$(csvcut -t -c id sites-groups.tsv | grep -v id)
END_GROUP_LOOP
fi

getData sites/${SITEID}/users .users.user[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.fullName,.email,.siteRole,.lastLogin

# loop over all users to get favorites and workbook list
if [ $(grep -v id sites-users.tsv | wc -l | awk '{print $1}') != "0" ]
then
	while IFS=',' read USERID
	do
		getData sites/${SITEID}/favorites/${USERID} .favorites.favorite[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.userid,.workbook.id,.view.id,.label	
		getData sites/${SITEID}/users/${USERID}/workbooks .workbooks.workbook[] _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.userid,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin
	done << END_USER_LOOP
$(csvcut -t -c id sites-users.tsv | grep -v id)
END_USER_LOOP
fi
}

server_cnt=$(echo "$(jq '.servers.server | length' ../config.json) - 1" | bc )

clean

for i in $(seq 0 ${server_cnt})
do
	echo
	server=$(jq -r ".servers.server[$i].name" ../config.json)
	server_url=$(jq -r ".servers.server[$i].url" ../config.json)
	api_url="${server_url}/api/"$(jq -r ".servers.server[$i].api_version" ../config.json)

	jq -c ".servers.server[$i].credentials | {credentials:.}" ../config.json > req.json	

	auth signin
	getServerData
	# get views in default site
	echo
	echo "${SITEID} (default site)"
	getSiteData

	# loop over all other sites
	while IFS=',' read SITEID SITENAME SITEURL
	do
		echo
		echo "${SITENAME}"
		auth switchSite ${SITEURL}
		getSiteData
	done << END_SITE_LOOP
$(csvcut -t -c id,name,contentUrl sites.tsv | grep -v 'id,name,contentUrl' | grep -v ',$')
END_SITE_LOOP

	auth signout
done

clean
