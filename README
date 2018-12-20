# tab-api

a bash script to get server data from tableau server instances

## requirements

- [`jq`](https://stedolan.github.io/jq/) for all your json querying and manipulation needs on terminal
- [`csvkit`](https://csvkit.readthedocs.io/) for all your plain-text, flat-file querying and manipulation need on terminal 

## configuration

`get-server-data.sh` reads server configuration(s) from `config.json`; see `example-config.json` for an example configuration file.

Developed and tested against self-hosted tableau servers; not clear how well this will work against tableau-hosted tableau servers.

## api calls used

for more details, read the [api docs](https://onlinehelp.tableau.com/v10.5/api/rest_api/en-us/help.htm#REST/rest_api.htm).

- server stuff
  - `auth/signin` -- authenticating with the server
  - `auth/switchSite` -- for hitting different sites on the server
  - `auth/signout` -- for politely logging off the server
  - `serverinfo` -- basic information about the server
  - `sites` -- list of sites on server
  - `schedules` -- list of schedules on server
  - server-site stuff
    - `sites/<SITEID>/tasks/extractRefreshes` -- list of datasources on site set up with scheduled extract refreshes
    - `sites/<SITEID>/datasources` -- list of datasources on site
    - `sites/<SITEID>/groups` -- list of groups on site
    - `sites/<SITEID>/projects` -- list of projects on site
    - `sites/<SITEID>/subscriptions` -- list of subscriptions on site
    - `sites/<SITEID>/users` -- list of users on site
    - `sites/<SITEID>/workbooks` -- list of workbooks on site
    - `sites/<SITEID>/views` -- list of views on site
    - server-site-datasource stuff
      - `sites/<SITEID>/datasources/<DATASOURCEID>/revisions` -- list of revisions for datasources. version history has to be turned on for the site
    - server-site-group stuff
      - `sites/<SITEID>/groups/<GROUPID>/users` -- list of users in groups
    - server-site-user stuff
      - `sites/<SITEID>/users/<USERID>/workbooks` -- list of workbooks users have access to
      - `sites/<SITEID>/favorites` -- list of favorice workbooks & views for users
    - workbook-level stuff
      - `sites/<SITEID>/workbooks/<WORKBOOKID>/revisions` -- list of revisions for workbooks

## output

aside from `auth/*` calls, separate tab-delimited files will be created for each of the api calls used
