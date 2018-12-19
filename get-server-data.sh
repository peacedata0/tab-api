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

## v1.0.1 - 2018-12-19 - RK
added siteurl (contentUrl) to outputs to enable creating complete links
changed output to be more specific about which server and site is currently being queried

## v1.0.0 - 2018-12-13 - RK
Initial version

_SCRIPT_DOCUMENTATION_

page_size=1000		# 1-1000

cd output/

function clean(){
	rm *.json
	for f in sites*.tsv schedules.tsv; do
		rm ${f}
		mv _${f} ${f}
	done
}

function appendData(){
	if [ ! -f _${1} ] ; then
		cp ${1} _${1}
	else
		tail -n+2 ${1} >> _${1}
	fi
}

function auth(){
#	echo "${FUNCNAME[0]} ${1}"
	local t=''
	if [ "${1}" == "signin" ]; then
		t="-d @req.json"
	elif [ "${1}" == "switchSite" ]; then
		jq -nc --arg u "${2}" '.site.contentUrl=$u' > req.json
		t="-H ${TOKEN} -d @req.json"
	else
		t="-H ${TOKEN}"
	fi
	curl --silent -X POST --url "${api_url}/auth/${1}" -H "Content-type:application/json" -H "Accept:application/json" ${t} --out auth.json
	if [ "${1}" != "signout" ]; then
		TOKEN="X-Tableau-Auth:$(jq ".credentials.token" auth.json | cut -f 2 -d\")"
		SITEID=$(jq ".credentials.site.id" auth.json | cut -f 2 -d\")
		SITEURL=$(jq ".credentials.site.contentUrl" auth.json | cut -f2 -d\")
	fi
}

function getData(){ # getData endpoint .json.root .list,.of,.json.nodes.to.keep optional_constant_name optional_constant_value
#	echo "${FUNCNAME[0]}"
	local URL=${api_url}/$1
	fileout=$(echo "${1}" | sed "s/\/${SITEID}\//-/g" | sed "s/\/${USERID}\//-/g")
	local current_page=0
	local total_pages=1
	local total_count=0
	local argjson=""
	local JQ_FILTER=""
	if [ "${4}" != "" ]; then
		argjson="--argjson _ ${4}"
		JQ_FILTER=${3//_X_/\$_}
	else
		JQ_FILTER="${3}"
	fi
	echo ${JQ_FILTER//./} | tr ',' '\t' | tr -d '[$]' > ${fileout}.tsv # strip '.[]' and convert csv to tsv
	until [ ${current_page} -eq ${total_pages} ]; do
		current_page=$((current_page+1))
		curl -s -X GET -H ${TOKEN} -H "Accept:application/json" \
			--url "${URL}?fields=_all_&pageSize=${page_size}&pageNumber=${current_page}"\
			--out ${fileout}.json
		total_count=$(jq -r '.pagination.totalAvailable' ${fileout}.json)
		if [ ${total_count} != "null" ] && [ ${total_count} -gt 0 ]; then
			jq -r ${argjson} "$2[] | [ ${JQ_FILTER} ] | @tsv" ${fileout}.json >> ${fileout}.tsv
			total_pages=$(( ${total_count} / ${page_size} + 1 ))
			appendData ${fileout}.tsv
		fi
		echo "${server} - ${SITEURL} - ${fileout} - N=${total_count} - batch ${current_page} of ${total_pages}"
		/bin/sleep 0.1s
	done
}

server_cnt=$(echo "$(jq '.servers.server | length' ../config.json) - 1" | bc )

clean

for i in $(seq 0 ${server_cnt}); do
	echo
	server=$(jq -r ".servers.server[$i].name" ../config.json)
	server_url=$(jq -r ".servers.server[$i].url" ../config.json)
	api_url="${server_url}/api/"$(jq -r ".servers.server[$i].api_version" ../config.json)
	
	jq -c ".servers.server[$i].credentials | {credentials:.}" ../config.json > req.json	

	auth signin

	getData sites .sites.site _X_.serverurl,_X_.server,.id,.name,.contentUrl,.adminMode,.state,.revisionHistoryEnabled,.subscribeOthersEnabled,.guestAccessEnabled,.cacheWarmupEnabled,.commentingEnabled "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\"}"

	getData schedules .schedules.schedule _X_.serverurl,_X_.server,.id,.name,.state,.priority,.createdAt,.updatedAt,.type,.frequency,.nextRunAt "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\"}"

	# get views in default site
	echo
	echo "${SITEID} (default site)"

	getData sites/${SITEID}/subscriptions .subscriptions.subscription _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.subject,.content.id,.content.type,.schedule.id,.schedule.name,.user.id,.user.name "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/datasources .datasources.datasource _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.type,.createdAt,.updatedAt,.isCertified,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/projects .projects.project _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.description,.contentPermissions "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/workbooks .workbooks.workbook _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/views .views.view _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.createdAt,.updatedAt,.workbook.id,.workbook.name,.workbook.contentUrl,.workbook.showTabs,.workbook.size,.workbook.createdAt,.workbook.updatedAt,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin,.project.id,.project.name,.project.description,.usage.totalViewCount "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/users .users.user _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.fullName,.email,.siteRole,.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	getData sites/${SITEID}/groups .groups.group _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.domain.name "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

	# loop over all users to get workbook list
	while IFS=',' read SITEID USERID; do
		getData sites/${SITEID}/users/${USERID}/workbooks .workbooks.workbook _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.userid,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\",\"userid\":\"${USERID}\"}"
	done << END_USER_LOOP
$(csvcut -t -c _siteid,id sites-users.tsv | grep -v 'siteid,id')
END_USER_LOOP

	# loop over all other sites
	while IFS=',' read SITEID SITENAME SITEURL; do
		echo
		echo "${SITENAME}"
		auth switchSite ${SITEURL}

		getData sites/${SITEID}/subscriptions .subscriptions.subscription _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.subject,.content.id,.content.type,.schedule.id,.schedule.name,.user.id,.user.name "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/datasources .datasources.datasource _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.type,.createdAt,.updatedAt,.isCertified,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/projects .projects.project _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.description,.contentPermissions "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/workbooks .workbooks.workbook _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/views .views.view _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.contentUrl,.createdAt,.updatedAt,.workbook.id,.workbook.name,.workbook.contentUrl,.workbook.showTabs,.workbook.size,.workbook.createdAt,.workbook.updatedAt,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin,.project.id,.project.name,.project.description,.usage.totalViewCount "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/users .users.user _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.fullName,.email,.siteRole,.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		getData sites/${SITEID}/groups .groups.group _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,.id,.name,.domain.name "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\"}"

		# loop over all users to get workbook list
		while IFS=',' read SITEID USERID; do
			getData sites/${SITEID}/users/${USERID}/workbooks .workbooks.workbook _X_.serverurl,_X_.server,_X_.siteid,_X_.siteurl,_X_.userid,.id,.name,.contentUrl,.showTabs,.size,.createdAt,.updatedAt,.project.id,.project.name,.project.description,.owner.id,.owner.name,.owner.fullName,.owner.email,.owner.siteRole,.owner.lastLogin "{\"serverurl\":\"${server_url}\",\"server\":\"${server}\",\"siteid\":\"${SITEID}\",\"siteurl\":\"${SITEURL}\",\"userid\":\"${USERID}\"}"
		done << END_USER_LOOP
$(csvcut -t -c _siteid,id sites-users.tsv | grep -v 'siteid,id')
END_USER_LOOP

	done << END_SITE_LOOP
$(csvcut -t -c id,name,contentUrl sites.tsv | grep -v 'id,name,contentUrl' | grep -v ',$')
END_SITE_LOOP

	auth signout
done

clean
