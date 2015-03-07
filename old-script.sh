#
# Generates systemd services
#

DATA_DIR=/mnt/data

me=`basename $0`
function usage(){
  echo "Usage: $me <ProjectName> <InstanceName> stdin:AppDefinition"
  echo "   ProjectName         Name of the project"
  echo "   InstanceName        Unique name of this instance"
  echo "   AppDefinition       The application definition (yml) is read from the standard input"
  echo ""
  echo "Example: cat myAppDef.yml | $me Project1 Instance1"
  exit 1
}
if [ $# -lt 2 ]; then
  usage
fi

project=$1
instance=$2
params="${*:3}"

echo $project
echo $instance
echo "$params"

names=()
r="$project-$instance"

if [ -d "./$r" ]; then
  rm -rf ./$r
fi

startscript=./$r/start.sh
stopscript=./$r/stop.sh
mainservice=./$r/main\@$project-$instance.service

mkdir -p ./$r

function var {
  name=$1
  echo "${!name}"
}
function trim {
  echo "$1" | sed -e 's/^ *//' -e 's/ *$//'
}
function startScript {
  echo $1 >> $startscript
}
function stopScript {
  echo $1 >> $stopscript
}
function mainService {
  echo $1 >> $mainservice
}
function script {
  echo $2 >> ./$r/$1
}
function subst {
  text="$1"
  keys=$(echo $params | /opt/bin/jq keys[])
  while read -r key
  do
    value=$(echo "$params" | /opt/bin/jq .["$key"])
    text=$(echo "$text" | sed "s/{{${key:1:-1}}}/${value:1:-1}/g")
  done <<<"$keys"
  echo "$text"
}

read -r appNameVersion                                # first line is the name of the app:version
appName=$(echo $appNameVersion | cut -d ':' -f 1)
appVersion=$(echo $appNameVersion | cut -d ':' -f 2-)
if [ "$appName" = "$appVersion" ]; then appVersion="unknown"; fi

while read -r line; do                                # read each line
  line=$(subst "$line")
  opt=$(echo $line | cut -d ':' -f 1)                 # part before : is the option
  val=$(trim "$(echo $line | cut -d ':' -f 2-)")      # part after : is the value
  if [ ${#opt} == 0 ]; then continue; fi              # skip blank lines
  if [ ${opt:0:1} == '#' ]; then continue; fi         # skip comments
  if [ ${opt:0:2} == '//' ]; then continue; fi
  if [ ${#val} == 0 ]; then                           # if no value, consider this key to be
    name=$opt                                         # the name of the container
    names+=($name)                                    # add the name to the array
  fi
  opt=${opt/\-/_}                                     # replace dash (-) in varname with underscore (_)
  varname=$name\_$opt                                 # create vars like name_opt
  eval $varname="\$val"
done

#progress indication
/usr/bin/etcdctl --peers http://docker1.rni.org:4001 rm /instances/$project/$appName/$instance --recursive
/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/state loading
/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/appName "$appName"
/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/appVersion "$appVersion"
/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/parameters "$params"

# generate main unit
mainService "[Unit]"
mainService "Description=Main unit for $project-$instance"
mainService "Requires=docker.service"
for name in "${names[@]}"; do
  service="$name@$project-$instance.service"
  networkservice="net-$name@$project-$instance.service"
  #startScript "systemctl destroy $service"
  #startScript "systemctl destroy $networkservice"
done
#startScript "systemctl destroy main@$project-$instance.service"
startScript "sleep 5"
#startScript "systemctl load main@$project-$instance.service"

for name in "${names[@]}"; do
  datadir="$DATA_DIR/$project/$instance/$name"
  image=`var $name\_image`
  opts=`var $name\_opts`
  ports=`var $name\_ports`
  links=`var $name\_links`
  volumes=`var $name\_volumes`
  volumesfrom=`var $name\_volumes\_from`
  args=`var $name\_args`
  dockername=$name-$project-$instance
  service="$name@$project-$instance.service"
  networkservice="net-$name@$project-$instance.service"

  # the main-service requires this service to be started
  mainService "BindsTo=$service"
  mainService "BindsTo=$networkservice"
  mainService "After=$service"
  mainService "After=$networkservice"

  #startScript "systemctl load $service"
  #startScript "systemctl load $networkservice"

  script $service "[Unit]"
  script $service "Description=Unit for $service"
  script $service "Requires=docker.service"
  script $service "PartOf=main@$project-$instance.service"
  for link in $links; do
    script $service "BindsTo=$link@$r.service"
    script $service "After=$link@$r.service"
  done
  script $service "[Service]"
  #script $service "LimitNOFILE=64000"
  script $service "TimeoutStartSec=0"
  script $service "TimeoutStopSec=25"
  script $service "EnvironmentFile=/etc/environment"
  script $service "ExecStartPre=-/usr/bin/docker kill $dockername"
  script $service "ExecStartPre=-/usr/bin/docker rm $dockername"
  script $service "ExecStartPre=/usr/bin/docker pull $image"
  linkage=""
  for link in $links; do
    linkage="$linkage--link $link-$project-$instance:$link "
  done
  volumestr=""
  for volume in $volumes; do
    mkdir -p $datadir$volume
    chmod a+rw $datadir$volume
    if [[ "$volume" == *:volatile ]]; then
      volumestr="$volumestr -v ${volume/\:volatile/} "
    else
      volumestr="$volumestr -v $datadir$volume:$volume "
    fi
  done
  volumesfromstr=""
  for volumefrom in $volumesfrom; do
    volumesfromstr="$volumesfromstr--volumes-from $volumefrom-$project-$instance "
  done
  script $service "ExecStartPre=/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/state activating"
  for link in $links; do
    script $service "ExecStartPre=/usr/bin/bash -c \"while [ -z \\\"\\\$(docker ps | grep $link-$project-$instance)\\\" ]; do sleep 5; done\""
  done
  script $service "ExecStart=/usr/bin/docker run --rm --name $dockername $linkage$volumestr$volumesfromstr$opts -v /usr/share/zoneinfo/localtime:/etc/localtime:ro -P $image $args"
  #script $service "ExecStartPost=/usr/bin/bash -c \"sleep 2\""
  script $service "ExecStop=/usr/bin/docker stop -t 30 $dockername"
  #script $service "[X-Fleet]"
  #script $service "MachineOf=main@$project-$instance.service"

  #network unit
  script $networkservice "[Unit]"
  script $networkservice "Description=Network unit for $service"
  script $networkservice "Requires=docker.service"
  script $networkservice "BindsTo=$service"
  script $networkservice "After=$service"
  script $networkservice "PartOf=$service"
  script $networkservice "[Service]"
  script $networkservice "ExecStartPre=-/usr/bin/docker kill publicnetwork-$dockername"
  script $networkservice "ExecStartPre=-/usr/bin/docker rm publicnetwork-$dockername"
  script $networkservice "ExecStartPre=/usr/bin/sleep 10"
  script $networkservice "ExecStart=/usr/bin/bash /opt/bin/create-network-container.sh $dockername _IF_NAME" #eno1
  script $networkservice "ExecStartPost=/usr/bin/bash /opt/bin/add-route.sh $dockername"
  script $networkservice "ExecStartPost=/usr/bin/bash /opt/bin/create-skydns-entry.sh $dockername http://docker1.rni.org:4001/v2/keys/skydns/ictu/$project/$instance/$name"
  script $networkservice "ExecStartPost=/usr/bin/bash /opt/bin/publish-app-info.sh $dockername http://docker1.rni.org:4001 $project $appName $appVersion $instance $name"
  script $networkservice "ExecStop=-/usr/bin/bash -c \"/opt/bin/delete-route.sh $dockername;/usr/bin/docker stop publicnetwork-$dockername;/usr/bin/docker rm publicnetwork-$dockername\""
  script $networkservice "ExecStopPost=-/usr/bin/curl -X DELETE http://docker1.rni.org:4001/v2/keys/skydns/ictu/$project/$instance/$name"
  script $networkservice "Type=oneshot"
  script $networkservice "RemainAfterExit=yes"
  #script $networkservice "[X-Fleet]"
  #script $networkservice "MachineOf=$service"
done

  # main-service
  mainService "[Service]"
  mainService "ExecStartPre=/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/state activating"
  mainService "ExecStart=/usr/bin/etcdctl --peers http://docker1.rni.org:4001 set /instances/$project/$appName/$instance/meta_/state active"
  mainService "ExecStop=/usr/bin/etcdctl --peers http://docker1.rni.org:4001 rm /instances/$project/$appName/$instance --recursive"
  mainService "Type=oneshot"
  mainService "RemainAfterExit=yes"

startScript "sudo systemctl start main@$project-$instance.service"
stopScript "sudo systemctl stop main@$project-$instance.service"
#stopScript "systemctl destroy *@$project-$instance.service"

chmod +x $startscript $stopscript
cd ./$r/ && sudo cp *.service /etc/systemd/system
sudo systemctl daemon-reload
./start.sh
#cd ./$r/ && ./start.sh
#echo {\"aap\":\"test\"}
