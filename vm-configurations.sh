####  Functions in this file should be used AFTER ISO's are created and pushed to esxi

function parse_json()
{
    echo $1 | \
    sed -e 's/[{}]/''/g' | \
    sed -e 's/", "/'\",\"'/g' | \
    sed -e 's/" ,"/'\",\"'/g' | \
    sed -e 's/" , "/'\",\"'/g' | \
    sed -e 's/","/'\"---SEPERATOR---\"'/g' | \
    awk -F=':' -v RS='---SEPERATOR---' "\$1~/\"$2\"/ {print}" | \
    sed -e "s/\"$2\"://" | \
    tr -d "\n\t" | \
    sed -e 's/\\"/"/g' | \
    sed -e 's/\\\\/\\/g' | \
    sed -e 's/^[ \t]*//g' | \
    sed -e 's/^"//'  -e 's/"$//'
}

function getVMCount {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  vm_ct=$(parse_json "$vm_str" "count")
  echo $vm_ct
}

function vm_definitions {
  option="${1}"
  case $option in
    "control")
        echo '{
            "count":"3",
            "cpu":"8",
            "memory":"32",
            "drive_string":"HP-Disk:200,HP-Disk:300",
            "network_string":"Openstack-Internal-Static,Openstack-External-Static"
          }'
    ;;
    "network")
        echo '{
            "count":"2",
            "cpu":"4",
            "memory":"16",
            "drive_string":"HP-Disk:100",
            "network_string":"Openstack-Internal-Static,Openstack-External-Static,Openstack-External-Static"
          }'
    ;;
    "compute")
        echo '{
            "count":"1",
            "cpu":"24",
            "memory":176",
            "drive_string":"HP-SSD:800,HP-Disk:400",
            "network_string":"Openstack-Internal-Static,Openstack-External-Static,Openstack-External-Static"
          }'
    ;;
    "monitoring")
        echo '{
            "count":"1",
            "cpu":"4",
            "memory":"16",
            "drive_string":"HP-Disk:200",
            "network_string":"Openstack-Internal-Static,Openstack-External-Static"
          }'
    ;;
    "storage")
        echo '{
            "count":"1",
            "cpu":"4",
            "memory":"32",
            "drive_string":"HP-Disk:250,HP-Disk:250,HP-SSD:250,HP-SSD:250,HP-SSD:250",
            "network_string":"Openstack-Internal-Static"
          }'
    ;;
    "kolla")
        echo '{
            "count":"1",
            "cpu":"8",
            "memory":"24",
            "drive_string":"HP-SSD:100",
            "network_string":"Openstack-Internal-Static,Openstack-External-Static"
          }'
    ;;
  esac
}

function create_vm {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  cpu_ct=$(parse_json "$vm_str" "cpu")
  memory_ct=$(parse_json "$vm_str" "memory")
  drive_string=$(parse_json "$vm_str" "drive_string")
  network_string=$(parse_json "$vm_str" "network_string")

  echo "creating VM name -> $2 type -> $1"
  esxi-vm-create -n ${2} --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/$2-iso.iso \
          -c $cpu_ct -m $memory_ct -S $DISK_NAME -v $drive_string -V \
          -N $network_string -o 'cpuid.coresPerSocket = "2",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              tools.syncTime = "TRUE"'

}