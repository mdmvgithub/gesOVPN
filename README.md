# gesOVPN

#### Small wizard for OpenVPN
This shell script is a small configurator for OpenVPN.
It allows to manage servers, certification authorities and its clients.
It is intended for users who do not want to struggle with technical details.

## Installation

### Manual
As _root_, run:
```
git clone https://github.com/mdmvgithub/gesOVPN.git
mv gesOVPN/gesovpn /usr/local/sbin
chmod 700 /usr/local/sbin/gesovpn
```

### Debian, Ubuntu
As _root_, run:
```
apt update
apt install -y apt-transport-https ca-certificates wget gnupg

wget -qO - https://repo.mobelt.com/keyFile | apt-key add -
echo 'deb https://repo.mobelt.com/all /' >/etc/apt/sources.list.d/mobelt.list
apt update
apt install -y gesovpn
 
```

## Features
All functions are through menus, it is not necessary to use other commands.
- Configure one o more servers, then enable, disable, start, stop them.
- Configure CAs.
- Create files for clients, with optional password.
- Set Static IPs for clients.
- Block clients for a server.

## First use
Just run `gesovpn`.
- It will show a form to set up basic settings for your server. 
- The next form allows you to configure your certification authority (CA).
- Then you can generate the `.ovpn` file for your first client.

Be patient with the generation of the DH params.

## Next use
Just run `gesovpn`. Now you can select an existing server or create one.
Several servers can share the same CA.
Certificate revocation is not contemplated, but clients can be selectively blocked for each server.
