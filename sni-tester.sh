#!/bin/bash

# set default settings
kubeconfig=~/.kube/config
repeat=1
counter=1
setupistio=0
workdir=/tmp/sni-tester
test_only=0
delete=0

# help text
usage()
{
    echo -e "\tusage: ./sni-tester.sh [-h]"
    echo -e "\tUse -k or --kubeconfig to sepcify kubeconfig file location. Default is env var KUBECONFIG = ~/.kube/config"
    echo -e "\tUse -c or --counter to specify where the next sni config should start. Default is 1"
    echo -e "\tUse -r or --repeat to sepcify how many sni configs should be generated. Default is 1"
    echo -e "\tUse -s or --setup to install Istio. Default is disabled"
    echo -e "\tUse -w or --workdir to sepcify the working directory e.g. to store the certificates. Default is /tmp/sni-tester"
    echo -e "\tUse -t or --test_only to only run test_only curls against all ingress gateways. Default is disbaled"
    echo -e "\tUse -d or --delete to delete all istio config & tmp dirs. Default is disbaled"
}

setup_istio()
{
    curl -s -L https://istio.io/downloadIstio | sh -
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
        -s | --setup )          setupistio=1
                                ;;
        -w | --workdir )        shift
                                workdir=$1
                                ;;
        -t | --test_only )      test_only=1
                                ;;
        -d | --delete )         delete=1
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
echo -e "\t-t = $test_only"
echo -e "\t-d = $delete"
echo -e "==="


if [ "$test_only" -eq 1 ]; then
    export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    export INGRESS_HOST=$(ifconfig ens3 | grep 'inet' | cut -d ' ' -f 10 | awk 'NR==1{print $1}')

    for (( i=1; i<=$repeat; i++ )); do 
        curl -s -HHost:$(printf "%05d" $i).example.com --resolve "$(printf "%05d" $i).example.com:$SECURE_INGRESS_PORT:$INGRESS_HOST" --cacert /tmp/sni-tester/example.com.crt "https://$(printf "%05d" $i).example.com:$SECURE_INGRESS_PORT/headers" | jq '.headers.Host'
    done
elif [ "$delete" -eq 1 ]; then
    rm -rf /tmp/sni-tester
    for (( i=1; i<=$repeat; i++ )); do 
        kubectl delete gw -n istio-system gateway-$(printf "%05d" $i)
        kubectl delete secret -n istio-system credential-$(printf "%05d" $i)
        kubectl delete vs -n istio-system vs-$(printf "%05d" $i)
    done
    kubectl delete se -n istio-system external-httpbin
    kubectl delete dr -n istio-system external-httpbin
else
    if [ "$setupistio" -eq 1 ]; then
        echo -e "\tSetting up Istio"
        setup_istio
    fi

    if [ ! -d "$workdir" ]; then
        mkdir $workdir
    fi

    if [ ! -f "$workdir/example.com.crt" ]; then
        openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=example.com' -keyout $workdir/example.com.key -out $workdir/example.com.crt
    fi

    # create service entry and destionation used by all
    # hint: cat is not indented so EOF works

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

    while [ "$repeat" -gt 0 ]; do
        # create certificate
        openssl req -out $workdir/$(printf "%05d" $counter).example.com.csr -newkey rsa:2048 -nodes -keyout $workdir/$(printf "%05d" $counter).example.com.key -subj "/CN=$(printf "%05d" $counter).example.com/O=example organization"
        openssl x509 -req -days 365 -CA $workdir/example.com.crt -CAkey $workdir/example.com.key -set_serial 0 -in $workdir/$(printf "%05d" $counter).example.com.csr -out $workdir/$(printf "%05d" $counter).example.com.crt
        kubectl --kubeconfig $kubeconfig create -n istio-system secret tls credential-$(printf "%05d" $counter) --key=$workdir/$(printf "%05d" $counter).example.com.key --cert=$workdir/$(printf "%05d" $counter).example.com.crt

        # create gateway
        cat << EOF | kubectl --kubeconfig $kubeconfig apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: gateway-$(printf "%05d" $counter)
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https-$(printf "%05d" $counter)
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: credential-$(printf "%05d" $counter)
    hosts:
    - $(printf "%05d" $counter).example.com
---
# create virtual service
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: vs-$(printf "%05d" $counter)
  namespace: istio-system
spec:
  hosts:
  - $(printf "%05d" $counter).example.com
  gateways:
  - gateway-$(printf "%05d" $counter)
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
fi
