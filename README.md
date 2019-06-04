# `eni_ctl.sh`

If you need to manage a single ec2 instance, it is advantageous to use an autoscaling group comprised of a single host. This setup allows the ec2 instance to recover from failure without human intervention. However, each time a failure occurs, the host will return with a different ip address, acquired by dhcp. We can ensure that the ec2 instance always gets a consistent ip address by creating a separate elastic network interface (eni) and attaching it to the autoscaling ec2 instance on boot.

Once we have an eni, we give it a name (using the `Name` tag), which matches the name of the autoscaling group. On initial boot, `eni_ctl.sh` is invoked from `systemd`. It determines which autoscaling group the ec2 instance belongs to, then locates and attaches the eni that has the same name. This ensures that the ec2 instance always finds the eni associated with the autoscaling group. The script assumes that the ec2 host has the appropriate permissions (using IAM) to query autoscaling groups, and to query and attach elastic network interfaces. Typically, I use `terraform` to manage the autoscaling groups, the elastic network interfaces (and elastic ips if needed), and the IAM profile required by the autoscaling group. See http://github.com/brukshut/nat_instance for an example. The script also requires `jq`.

`eni_ctl.sh` takes one of two arguments, either attach or detach.
```
[damascus.local:~/Desktop/workspace/eni_ctl/scripts] cgough% ./eni_ctl.sh
Usage: ./eni_ctl.sh [-a] [-d]
```
We typically invoke it from `systemd`:
```
[margat:~] cgough% cat /lib/systemd/system/eni.service
[Unit]
Description=eni control script

[Service]
ExecStart=/usr/local/sbin/eni_ctl.sh -a

[Install]
WantedBy=multi-user.target
```
Once the eni is attached, a separate script `add_routes.sh` gets invoked, which sets up separate ip route tables for the primary ip address (acquired via dhcp) as well as our newly attached eni. This ensures correct routing of traffic, and allows the eni to to reside on the same subnet as the primary interface of the ec2 instance. Typically, I will create an additional subnet for static addresses to avoid collisions with dhcp and to ensure that the static ip requested for the eni is always available.

This script gets invoked after the eni is plumbed, in `/etc/network/interfaces`:
```
[margat:~] cgough% cat /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
  up /usr/local/sbin/add_routes.sh -d eth0 || true
allow-hotplug eth0
iface eth0 inet6 manual
  up /usr/local/sbin/inet6-ifup-helper
  down /usr/local/sbin/inet6-ifup-helper
iface eth1 inet dhcp
  up /usr/local/sbin/add_routes.sh -d eth1 || true
allow-hotplug eth1
```
If the eni is already attached to the host, you can see its details in `/etc/default/eni`:
```
[margat:~] cgough% cat /etc/default/eni
FQDN=margat.gturn.nt
IP=10.0.1.22
GW=10.0.1.1
DEVICE=eth1
ASG_NAME=test-nat
INSTANCE_ID=i-07d783501a2d237be
ENI_ID=eni-0ff5b063faaa21473
ATTACHMENT_ID=null
```
## IAM permissions
The autoscaling group requires a policy so that the ec2 instance running the script can determine which autoscaling group it belongs to and which network interface has the same `Name`. It also needs to be able to attach and detach the interface. Here is an example `terraform` IAM policy document that defines these privileges:
```
data "aws_iam_policy_document" "document" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:DescribeAutoScalingInstances",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:DescribeNetworkInterfaces",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:DetachNetworkInterface",
      "ec2:AttachNetworkInterface",
    ]

    resources = ["*"]
  }
}
```
