#!/bin/sh
# tuned [script] plugin entry point. Called with "start" on profile activation
# and "stop" on deactivation.
case "$1" in
	start) exec /usr/local/bin/glymur-cpu-profile.sh balanced ;;
	stop)  exec /usr/local/bin/glymur-cpu-profile.sh reset ;;
esac
exit 0
