for c in {1..10..1}; do
curl http://localhost:8181/stop-app/innovation/libre$c
#curl http://localhost:8181/stop-app/innovation/test$c
done
