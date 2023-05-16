## OpenVPN Server Setup

## 1. Introduction

This project has the goal to automate the setup of a OpenVPN Server.

## 2. Maintainers

- [Felipe Vilarinho](https://www.linkedin.com/in/fvilarinho)

If you want to collaborate in this project, reach out us by e-Mail.

## 3. Requirements

This script works on the following Linux distributions:

- [`Debian 10 or later`](https://www.debian.org/)
- [`Ubuntu LTS 18 or later`](https://ubuntu.com/)
- [`Fedora in any version`](https://fedoraproject.org/)
- [`CentOS 7 or 8`](https://www.centos.org/)
- [`Amazon Linux 2`](https://aws.amazon.com/amazon-linux-2/?amazon-linux-whats-new.sort-by=item.additionalFields.postDateTime&amazon-linux-whats-new.sort-order=desc)
- [`Oracle Linux 8`](https://www.oracle.com/linux/)
- [`Arch Linux in any version`](https://archlinux.org/)

It's possible to work on other OSes, but it will need customization.

To run the script, it's necessary to have root privileges or be a sudo user.

## 4. How to run?

Basically, you just need to execute the `setup.sh` file and follow the steps below:

1. Define/confirm your public IP address.
2. Define the VPN Server network address mask (/24).
3. Define/confirm the VPN Server network port.
4. Define/confirm if the VPN Server will listen in TCP or UDP.
5. Define/confirm the DNS resolver.
6. Define/confirm if you want to use compression in the VPN tunnels.
7. Define/confirm the compression algorithm if you chose to use compression.
8. Define/confirm the encryption settings.
9. Define/confirm the default VPN client name.
10. Define/confirm the default VPN client password.

The setup is interactive but if you want to do an unattended setup, set the following environment variables before:

- `AUTO_INSTALL=y`: Enable unattended setup with default values.
- `APPROVE_IP=y`: Use the public IP of your machine or network.
- `SERVER_NETWORK_ADDRESS_PREFIX`: Define the VPN Server network address mask (/24). Default value is `10.8.0.0`
- `PORT_CHOICE`: Define/confirm the VPN Server network port. Default value is `1194`.
- `PROTOCOL_CHOICE`: Define/confirm if the VPN Server will listen in TCP or UDP. Default value is `UDP`.
- `DNS`: Define/confirm the DNS resolver. Default value will be your machine or network DNS resolver.
- `COMPRESSION_ENABLED`: Define/confirm if you want to use compression in the VPN tunnels. Default value is `n`.
- `CUSTOMIZE_ENC`:  Define/confirm the compression algorithm if you chose to use compression. Default value is `n`.
- `CLIENT`: Define/confirm the default VPN client name. Default value is `client`.
- `PASS`: Define/confirm the default VPN client password. Default value is `passwordless`.

After that, the script will generate the client/server certificates based on the previous settings, install all required
software based on the machine operating system and set up the startup script.

Once the VPN Server is running, you will be able to connect into the VPN Server.

If you execute the `setup.sh` again, you will be able to create a new client, revoke existing client or uninstall the 
VPN Server.

## 5. Credits

This script was customized based on this [project](https://github.com/angristan/openvpn-install) 

And that's all! Enjoy!