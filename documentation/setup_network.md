# Network SR-IOV Configuration

For a system that has NICs that support network SR-IOV, a default number of Virtual Functions (VFs) is created per NIC during host setup.
Nevertheless, users can choose to customize the number of VFs per NIC after the initial round of host setup.

First, ensure that all guests are shut off and not running.

    $ virsh list --all
     Id   Name        State
    ----------------------------
     -    ubuntu      shut off
     -    windows11   shut off

Next, run the following command (where N is the number of VFs per NIC):

    $ ./host_setup/ubuntu/setup_network.sh --sriov-vfs N

Lastly, check the virtual function devices created (e.g. 4 VFs for a NIC):

    $ lspci | grep "Virtual Function"
    0000:01:02.0 Ethernet controller: Intel Corporation Ethernet Virtual Function 700 Series (rev 02)
    0000:01:02.1 Ethernet controller: Intel Corporation Ethernet Virtual Function 700 Series (rev 02)
    0000:01:02.2 Ethernet controller: Intel Corporation Ethernet Virtual Function 700 Series (rev 02)
    0000:01:02.3 Ethernet controller: Intel Corporation Ethernet Virtual Function 700 Series (rev 02)

Note: N is limited by the total number of VFs supported by the NIC
