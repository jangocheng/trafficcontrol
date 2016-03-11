#!/bin/bash

# Script for running the Dockerfile for Traffic Stats.
# The Dockerfile sets up a Docker image which can be used for any new container;
# This script, which should be run when the container is run (it's the ENTRYPOINT), will configure the container.
#
# The following environment variables must be set (ordinarily by `docker run -e` arguments):
# TRAFFIC_OPS_URI
# TRAFFIC_OPS_USER
# TRAFFIC_OPS_PASS
# CERT_COUNTRY
# CERT_STATE
# CERT_CITY
# CERT_COMPANY

start() {
	service influxdb start
	service traffic_stats start
	service grafana-server start
	touch /opt/traffic_stats/var/log/traffic_stats/traffic_stats.log
	exec tail -f /opt/traffic_stats/var/log/traffic_stats/traffic_stats.log
}

init() {
	TMP_TO_COOKIE="$(curl -v -s -k -X POST --data '{ "u":"'"$TRAFFIC_OPS_USER"'", "p":"'"$TRAFFIC_OPS_PASS"'" }' $TRAFFIC_OPS_URI/api/1.2/user/login 2>&1 | grep 'Set-Cookie' | sed -e 's/.*mojolicious=\(.*\); expires.*/\1/')"
	echo "Got Cookie: $TMP_TO_COOKIE"

  TMP_IP=$IP
	TMP_DOMAIN=$DOMAIN
	TMP_GATEWAY=$GATEWAY

	TMP_CACHEGROUP_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/cachegroups.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["name"]=="mid-east"]; print match[0]')"
	echo "Got cachegroup ID: $TMP_CACHEGROUP_ID"

	TMP_SERVER_TYPE_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/types.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["name"]=="INFLUXDB"]; print match[0]')"
	echo "Got server type ID: $TMP_SERVER_TYPE_ID"

	TMP_SERVER_PROFILE_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/profiles.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["name"]=="INFLUXDB"]; print match[0]')"
	echo "Got server profile ID: $TMP_SERVER_PROFILE_ID"

	TMP_PHYS_LOCATION_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/phys_locations.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["name"]=="plocation-nyc-1"]; print match[0]')"
	echo "Got phys location ID: $TMP_PHYS_LOCATION_ID"

	TMP_CDN_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/cdns.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["name"]=="cdn"]; print match[0]')"
	echo "Got cdn ID: $TMP_CDN_ID"

	curl -v -k -X POST -H "Cookie: mojolicious=$TMP_TO_COOKIE" --data-urlencode "host_name=$HOSTNAME" --data-urlencode "domain_name=$TMP_DOMAIN" --data-urlencode "interface_name=eth0" --data-urlencode "ip_address=$TMP_IP" --data-urlencode "ip_netmask=255.255.0.0" --data-urlencode "ip_gateway=$TMP_GATEWAY" --data-urlencode "interface_mtu=9000" --data-urlencode "cdn=$TMP_CDN_ID" --data-urlencode "cachegroup=$TMP_CACHEGROUP_ID" --data-urlencode "phys_location=$TMP_PHYS_LOCATION_ID" --data-urlencode "type=$TMP_SERVER_TYPE_ID" --data-urlencode "profile=$TMP_SERVER_PROFILE_ID" --data-urlencode "tcp_port=80" $TRAFFIC_OPS_URI/server/create

	TMP_SERVER_ID="$(curl -s -k -X GET -H "Cookie: mojolicious=$TMP_TO_COOKIE" $TRAFFIC_OPS_URI/api/1.2/servers.json | python -c 'import json,sys;obj=json.load(sys.stdin);match=[x["id"] for x in obj["response"] if x["hostName"]=="'"$HOSTNAME"'"]; print match[0]')"
	echo "Got server ID: $TMP_SERVER_ID"

	curl -v -k -H "Content-Type: application/x-www-form-urlencoded" -H "Cookie: mojolicious=$TMP_TO_COOKIE" -X POST --data-urlencode "id=$TMP_SERVER_ID" --data-urlencode "status=ONLINE" $TRAFFIC_OPS_URI/server/updatestatus

	sed -i -- 's/"toUser": "admin"/"toUser": "'"$TRAFFIC_OPS_USER"'"/g' /opt/traffic_stats/conf/traffic_stats.cfg
	sed -i -- 's/"toPasswd": ""/"toPasswd": "'"$TRAFFIC_OPS_PASS"'"/g' /opt/traffic_stats/conf/traffic_stats.cfg
	sed -i -- 's#"toUrl": "https://localhost"#"toUrl": "'"$TRAFFIC_OPS_URI"'"#g' /opt/traffic_stats/conf/traffic_stats.cfg

	openssl req -newkey rsa:2048 -nodes -keyout /etc/ssl/influxdb.key -x509 -days 365 -out /etc/ssl/influxdb.crt -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_CITY/O=$CERT_COMPANY"

	cat /etc/ssl/influxdb.key /etc/ssl/influxdb.crt > /etc/ssl/influxdb.pem

	service influxdb start

	sleep 10

	influx -execute 'create database cache_stats'
	influx -execute 'create database deliveryservice_stats'
	influx -execute 'create database daily_stats'
	influx -execute 'create retention policy daily on cache_stats duration 26h replication 3 DEFAULT'
	influx -execute 'create retention policy daily on deliveryservice_stats duration 26h replication 3 DEFAULT'
	influx -execute 'create retention policy monthly on cache_stats duration 30d replication 3 DEFAULT'
	influx -execute 'create retention policy monthly on deliveryservice_stats duration 30d replication 3 DEFAULT'
	influx -execute 'create retention policy indefinite on daily_stats duration INF replication 3 DEFAULT'

	service influxdb stop

	sed -i -- 's/;protocol = http/protocol = https/g' /etc/grafana/grafana.ini
	sed -i -- 's#;cert_file =#cert_file = /etc/ssl/influxdb.crt#g' /etc/grafana/grafana.ini
	sed -i -- 's#;cert_key =#cert_key = /etc/ssl/influxdb.key#g' /etc/grafana/grafana.ini
	sed -i -n '1h;1!H;${g;s/access\n;enabled = false/access\nenabled = true/;p;}' /etc/grafana/grafana.ini

	echo "INITIALIZED=1" >> /etc/environment
}

source /etc/environment
if [ -z "$INITIALIZED" ]; then init; fi
start
