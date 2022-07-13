#!/bin/sh

# Create Namespace
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml

# Deploy metal LB resources
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# query for check metal LB Pod Resources Status
states=$(kubectl get pods -o=jsonpath-as-json='{.items[*].status.phase}' -n metallb-system)

# query for get DaemonSets that should be installed on node from Metal LB resources
metalLbDesiredPod=$(kubectl get ds -n metallb-system -o=jsonpath-as-json='{.items[*].status}')
totalSpeaker=$(jq -r '.[].desiredNumberScheduled' <<< $metalLbDesiredPod)

# Must +1 because there is controller for metallb pod deployment
totalSpeaker=$((totalSpeaker+1))

# Check state of Metal LB resources are ready
while true
do

  total=0
  for state in $(jq -r '.[]' <<< "$states");do
    if [ $state = Running ]
    then
      total=$((total+1))
    else
      echo "$state"
    fi
  done

  if [ $total -eq  $totalSpeaker ]
  then
    break
  fi
  sleep 5
  echo "Preparing the Metal LB Pod ..."
done

# Get Subnet of Kind Cluster
# It's needed for create ip subnet for Service
svcSubnet=$(jq -r '.[0].Subnet' <<< $(docker network inspect -f '{{json .IPAM.Config}}' kind))
metallbPod="192.168.1.1/24"

if [ svcSubnet != "" ]
then
  length=${#svcSubnet}
  metallbPod="${svcSubnet: 0: length-6}100.0/24"
fi

# Apply the configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $metallbPod
EOF