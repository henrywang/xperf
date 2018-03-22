#/ssh

The /ssh directory holds the SSH keys used by the xperf framework. Once you create your SSH keys to be used to communicate with the device under test (DUT), copy the keys to this directory if you'd like to use your own. Please append public key into $HOME/.ssh/authorized_keys before run xperf testing.

Some example SSH keys are provided and can be used with the xperf framework.

The keys are:

demo_id_rsa
An OpenSSH private key

demo_id_rsa.pub
An OpenSSH public key

