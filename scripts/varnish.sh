#!/bin/bash

VARNISH_BACKEND_ADDRESS=$1
VARNISH_BACKEND_PROTOCOL=$2
VHA_TOKEN=$3
DEFAULT_VARNISH=/etc/default/varnish
DEFAULT_HITCH=/etc/default/hitch
DEFAULT_VHA_AGENT=/etc/default/vha-agent
DEFAULT_DISCOVERY=/etc/default/varnish-discovery
VARNISH_DEFAULT_VCL=/etc/varnish/default.vcl
VHA_VCL=/etc/varnish/vha.vcl
VHA_NODE_CONF=/etc/varnish/nodes.conf
VHA_HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

TOTAL_MEM=$(free -m | grep Mem | awk -F" " {'print $2'})
TWO_OF_THREE_MEM=$(expr $(expr $TOTAL_MEM / 3) + $(expr $TOTAL_MEM / 3))

/usr/bin/vha-generate-vcl --token ${VHA_TOKEN} > ${VHA_VCL}

cat > $DEFAULT_VARNISH <<EOF
# Generated by CloudFormation

START=yes
NFILES=131072
MEMLOCK=82000

DAEMON_OPTS="-a :80 -a 127.0.0.1:8443,PROXY \\
             -T localhost:6082 \\
             -f /etc/varnish/default.vcl \\
             -S /etc/varnish/secret \\
             -s malloc,${TWO_OF_THREE_MEM}m \\
             -p vsl_reclen=4084"
EOF

cat > $DEFAULT_HITCH <<EOF
# Generated by CloudFormation

START=true
HITCH_OPTIONS="--config=/etc/hitch/hitch.conf"
EOF

cat > $VARNISH_DEFAULT_VCL <<EOF
# Generated by CloudFormation

vcl 4.0;
include "vha.vcl";

# Never used
backend dummy { .host = "0:0"; }

sub vcl_init {
	new default_origin = goto.dns_director("${VARNISH_BACKEND_PROTOCOL}://${VARNISH_BACKEND_ADDRESS}");
}

sub vcl_backend_fetch {
	set bereq.backend = default_origin.backend();
	# To clean up the backend request
	unset bereq.http.grace;
}

sub vcl_backend_response {
	if (beresp.status >= 500 && beresp.status < 600) {
		return (abandon);
	}
	# Maximum limit for grace
	set beresp.grace = 1d;
}

sub vcl_backend_error {
	# Retry the backend request if we're not happy with the response status.
	if (beresp.status >= 500 && beresp.status < 600) {
		set beresp.http.X-Retried = bereq.retries;
		return (retry);
	}
}

sub vcl_deliver {
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT";
	} else {
		set resp.http.X-Cache = "MISS";
	}
}
EOF

cat > $DEFAULT_VHA_AGENT <<EOF
# Generated by CloudFormation

ENABLE=1
DAEMON_OPTS="-N ${VHA_NODE_CONF} -m ${VHA_HOSTNAME} -s /var/lib/vha-agent/vha-status -T ${VHA_TOKEN}"
EOF

service hitch restart
service varnish restart
service vha-agent restart