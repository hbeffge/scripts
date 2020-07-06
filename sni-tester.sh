#!/bin/bash

# set default settings
kubeconfig=$KUBECONFIG
repeat=1
counter=1
setupistio=0

# help text
usage()
{
    echo -e "\tusage: ./sni-tester.sh [-h]"
    echo -e "\tUse -k or --kubeconfig to sepcify kubeconfig file location. Default is env var KUBECONFIG = $KUBECONFIG"
    echo -e "\tUse -r or --repeat to sepcify how many sni configs should be generated. Default is 1"
    echo -e "\tUse -c or --counter to specify the last position of the last created sni config. Default is 1"
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
echo -e "==="

# create certificate
# create gateway
# create virtual service
# create service entry
