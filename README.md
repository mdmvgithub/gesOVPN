# gesOVPN

#### Small wizard for OpenVPN
This shell script is a small configurator for OpenVPN.
It allows to manage servers, certification authorities and clients.
It is intended for users who do not want to struggle with technical details

## Installation
It requires to install `dialog`
As _root_, run
```
# git clone gesOVPN
# mv gesOVPN/gesOVPN.sh /usr/local/sbin
# chmod 700 /usr/local/sbin/gesOVPN.sh
```
## Features
All the features are through menus, no other commands need to be used.
- Configure one o more servers, then enable, disasble, start, stop.
- Configure CAs.
- Create files for clients, with optional password.
- Set Static IPs for clients.
- Block clients for one server.

## First use
Simply run `gesOVPN.sh`.
- It will show a form to set a basic configuration for your server. 
- Next form allows to setup your certification authority (CA).
- Then you can generate `.ovpn` files for your first client.

Be patient with DH params generation

## Next use
Simply run `gesOVPN.sh`. Now you can select an existing server or create one.
Several servers can share the same CA, but clients can be selectively blocked for each server.
