#!/bin/bash

# set default settings
kubeconfig=~/.kube/config
repeat=1
counter=1
setupistio=0
workdir=/tmp/sni-tester

# help text
usage()
{
    echo -e "\tusage: ./sni-tester.sh [-h]"
    echo -e "\tUse -k or --kubeconfig to sepcify kubeconfig file location. Default is env var KUBECONFIG = ~/.kube/config"
    echo -e "\tUse -c or --counter to specify the last position of the last created sni config. Default is 1"
    echo -e "\tUse -r or --repeat to sepcify how many sni configs should be generated. Default is 1"
    echo -e "\tUse -s or --setup to install Istio. Default is disabled"
    echo -e "\tUse -w or --workdir to sepcify the working directory e.g. to store the certificates. Default is /tmp/sni-tester"
}

setup_istio()
{
    curl -L https://istio.io/downloadIstio | sh -
    export PATH="$PATH:/root/istio-1.6.4/bin"
    istioctl --kubeconfig $kubeconfig install --set profile=default --set meshConfig.accessLogFile="/dev/stdout"
}


# arguments
while [ "$1" != "" ]; do
    case $1 in
        -k | --kubeconfig )     shift
                                kubeconfig=$1
                                ;;
        -c | --counter )        shift
                                counter=$1
                                ;;
        -r | --repeat )         shift
                                repeat=$1
                                ;;
        -s | --setup )          shift
                                setupistio=1
                                ;;
        -w | --workdir )        shift
                                workdir=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

echo -e "Starting execusion with the following parameters:"
echo -e "==="
echo -e "\t-k = $kubeconfig"
echo -e "\t-c = $counter"
echo -e "\t-r = $repeat"
echo -e "\t-s = $setupistio"
echo -e "\t-w = $workdir"
echo -e "==="

if [ "$setupistio" == 1 ]
then
    echo -e "\tSetting up Istio"
    setup_istio
fi

if [ ! -d "$workdir" ] 
then
    mkdir $workdir
fi

if [ ! -f "$workdir/example.com.crt" ]; then
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=example.com' -keyout $workdir/example.com.key -out $workdir/example.com.crt
fi

# create service entry and destionation used by all

cat << EOF | kubectl --kubeconfig $kubeconfig apply -f -
---
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: external-httpbin
  namespace: istio-system
spec:
  hosts:
  - httpbin.org
  location: MESH_EXTERNAL
  ports:
  - number: 443
    name: https-httpbin
    protocol: HTTPS
  resolution: DNS
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: external-httpbin
  namespace: istio-system
spec:
  host: "httpbin.org"
  trafficPolicy:
    tls:
      mode: SIMPLE
EOF

while [ "$repeat" -gt 0 ]
do
    # create certificate
    openssl req -out $workdir/$counter.example.com.csr -newkey rsa:2048 -nodes -keyout $workdir/$counter.example.com.key -subj "/CN=$counter.example.com/O=example organization"
    openssl x509 -req -days 365 -CA $workdir/example.com.crt -CAkey $workdir/example.com.key -set_serial 0 -in $workdir/$counter.example.com.csr -out $workdir/$counter.example.com.crt
    kubectl --kubeconfig $kubeconfig create -n istio-system secret tls credential-$counter --key=$workdir/$counter.example.com.key --cert=$workdir/$counter.example.com.crt
    
    # create gateway
    cat << EOF | kubectl --kubeconfig $kubeconfig apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: gateway-$counter
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https-$counter
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: credential-$counter
    hosts:
    - $counter.example.com
---
# create virtual service
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: vs-$counter
  namespace: istio-system
spec:
  hosts:
  - $counter.example.com
  gateways:
  - gateway-$counter
  http:
  - route:
    - destination:
        port:
          number: 443
        host: httpbin.org
---
EOF
    (( counter = counter + 1 ))
    (( repeat = repeat - 1 ))
done
