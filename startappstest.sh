for c in {1..10..1}; do
curl --data " curl -s http://docker1.rni.org:4001/v2/keys/apps/innovation/libreboard/latest | /opt/bin/jq -r '.node.value' | /opt/bin/start-app-nofleet.sh isd libre$c" http://localhost:8181/start-app/isd/libre$c --header "Content-Type:text/plain" 
done
