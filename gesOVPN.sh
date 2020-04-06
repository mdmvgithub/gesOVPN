#!/bin/bash

VERSION=0.9

# by mm AT nisu.org

# gesOVPN.sh configures openvpn server(s)

avisa () {
  dialog  --keep-tite --stdout --backtitle "$BCKTIT" \
    --title "${2:-Info}" \
    --msgbox "$1" 15 55
}
error () {
  avisa "$1" Error
  exit 1
}

espera () {
  dialog --keep-tite --stdout --backtitle "$BCKTIT" \
    --title "Wait" \
    --progressbox "$1"$'\n\nPelase wait ...\n\n ' 15 55
}

clean () {
  echo $1 | sed -e 's/[^0-9a-zA-Z\._]/_/g'
}

systemd () {
  systemctl daemon-reload > >(espera "Configuring systemd")
}
start ()  {
  service openvpn@$sv_fn start > >(espera "Starting server") ||
    error "Error starting server $sv_n_fn"
}
stop ()  {
  service openvpn@$sv_fn stop  > >(espera "Stopping server")
}

haz_subj () {
  local sbj=''
  for v in $* ; do
    q=${v#??_}
    q=${q^^*}
    s="$s/$q="$(eval echo '"$'$v'"' | sed -e 's/=/\\=/g' -e 's/\//\\\//g')
  done
  echo "$s"
}

cdr2mask () {
  set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
  [ $1 -gt 1 ] && shift $1 || shift
  echo ${1-0}.${2-0}.${3-0}.${4-0}
}

mk_conf () {
  (sed $(openssl version -d | sed -e 's/^OPENSSLDIR: *"\(.*\)"/\1/')/openssl.cnf \
    -e 's/^\(default_ca\s*=\).*/\1 CA_gen_OVPN/'
    cat - <<EOF
[ CA_gen_OVPN ]

dir             = $GESOVPN/ca-$ca_fn
certs           = \$dir
crl_dir         = \$dir
database        = \$dir/index.txt
#unique_subject = no
new_certs_dir   = \$dir

certificate     = \$dir/ca.pem
serial          = \$dir/serial
crlnumber       = \$dir/crlnumber
crl             = \$dir/crl.pem
private_key     = \$dir/key.pem

x509_extensions = usr_cert

name_opt        = ca_default
cert_opt        = ca_default

default_days    = 36500
default_crl_days= 30
default_md      = default
preserve        = no

policy          = policy_anything
EOF
  ) >$GESOVPN/openssl.cnf
}

lee_pwca () {
  [ "$pwca" ] || pwca=$(lee_pw_pk $GESOVPN/ca-$ca_fn/key.pem "CA KEY password") || return 1
}

# $1 fic $2 mens
lee_pw_pk () {
  local pw err
  echo '----' | openssl rsa -passin stdin -in $1 >/dev/null 2>&1 && echo -n '----' && return 0
  err=''
  while true; do
    pw=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
           --title "Password" --insecure \
           --passwordbox "$err"$'\n\n'"$2" 15 55 ""
        ) || return 1
    err=''
    echo -n "$pw" | openssl rsa -passin stdin -noout -in $1 >/dev/null && break
    err="*** Invalid password, retry ***"
  done
  echo -n "$pw"
}

# $1 mens
lee_nw_pw () {
  local pw pw2 err=''
  while true; do
    pw=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
           --title "New password" --insecure \
           --passwordbox $err$'\n'$1$'\nNew password (min 8)\nTo avoid password, type ---' 15 55 "" ) || return 1
    [ "$pw" == '---' ] && echo -n "$pw" && return 0
    pw2=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
           --title "New password" --insecure \
           --passwordbox 'The same passowrd again' 15 55 "" ) || return 1
    [ "$pw" == "$pw2" ] || { err='*** Mismatch ***' && continue; }
    [ "${#pw}" -ge 8 ] && break
    err='*** Short ***'
  done
  echo -n "$pw"
}

# $1 pw org $2 nueva $3 archivo
camb_pw_pk () {
  local x
  [ "$$1" == "$2" ] && return 0
  x=$(echo -n "$1" | openssl rsa -passin stdin -in $3) || return 1
  if [ "$2" == '---' ]; then
    echo "$x" | openssl rsa -out $3 >&2 || return 1
  else
    echo "$x" | openssl rsa -passout fd:3 -out $3 -aes256 >&2  3< <(echo -n "$2") || return 1
  fi
}

set_ca () {
  local x v nodes pwca2 cconf=$'cn\no\nou\nl\nst\nc'
  for v in fn $cconf; do # ahora mismo no sirve peroes por si se quiere copiar de otra
    eval local ca_n_$v ca_p_$v
    eval ca_n_$v=\$ca_$v
    eval ca_p_$v=\$ca_$v
  done
  while true ; do
    x=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
        --title "CA settings" \
        --form "Setting CA - Certification Authority" 19 55 0 \
               "Fullfill all the fields." 1 1 '' 1 1 0 0 \
               "The friendly name is only for administration use." 2 1 '' 2 1 0 0 \
               "It is not exposed to the users" 3 1 '' 3 1 0 0 \
               "    Friendly name"  4 1 "${ca_n_fn:-my_ca}" 4 19 ${ca_p_fn:-3}0 0 \
               "          CA Name"  6 1 "${ca_n_cn:-VPN}"   6 19 30 0 \
               "     Organization"  7 1 "$ca_n_o"           7 19 30 0 \
               "Organization Unit"  8 1 "${ca_n_ou:-VPN}"   8 19 30 0 \
               "         Locality"  9 1 "$ca_n_l"           9 19 30 0 \
               "State or Privince" 10 1 "$ca_n_st"         10 19 30 0 \
               "     Country (XX)" 11 1 "$ca_n_c"          11 19 3 0
     )
    [ "$x" ] || { ca_fn='' ; return 1; }
    echo "$x" | grep -q '^$' && continue 
    if [ "$ca_p_fn" ]; then
      read -d$'\1' -r ca_n_cn ca_n_o ca_n_ou ca_n_l ca_n_st ca_n_c < <(echo "$x")
    else
      read -d$'\1' -r ca_n_fn ca_n_cn ca_n_o ca_n_ou ca_n_l ca_n_st ca_n_c < <(echo "$x")
    fi
    [ "$ca_n_c" ] || continue # miro el último, cosas de dialog
    if [ "${#ca_n_c}" != 2 ]; then
      avisa "Country must be a TWO letter code" Error
      continue
    fi
    ca_n_fn=$(clean $ca_n_fn)
    [ "$ca_n_fn" ] || return 1
    if [ ! "$ca_p_fn" ] && [ -d "$GESOVPN/ca-$ca_n_fn" ]; then
      avisa "CA friendly name already exists" Error
      continue;
    fi
    break
  done
  mkdir $GESOVPN/ca-$ca_n_fn 2>/dev/null
  nodes=''
  pwca=$(lee_nw_pw "Password for CA") || return 1
  [ "$pwca" == '---' ] && nodes='--nodes'
  for v in $cconf; do
    eval vv=\$ca_n_$v
    echo ca_$v="'"$vv"'"
  done >$GESOVPN/ca-$ca_n_fn/conf
  source $GESOVPN/ca-$ca_n_fn/conf || { rm -rf $GESOVPN/ca-$ca_n_fn ; error "Config failed"; }
  echo -n "$pwca" |
    openssl req -new -newkey rsa:2048 -keyout $GESOVPN/ca-$ca_n_fn/key.pem \
                -subj "$(haz_subj ca_cn ca_o ca_ou ca_l ca_st ca_c)" \
                -out $GESOVPN/ca-$ca_n_fn/ca.pem -x509 -passout stdin $nodes \
                -days 36500 > >(espera "Generating CA cert") >&2 ||
    { rm -rf $GESOVPN/ca-$ca_n_fn ; error "CA Certificate generation failed"; }
  touch $GESOVPN/ca-$ca_n_fn/index.txt
  openssl rand -hex 4 >$GESOVPN/ca-$ca_n_fn/serial
  ca_fn=$ca_n_fn
  lc=$(ls -d $GESOVPN/ca-* 2>/dev/null)
}

set_srv () {
  local err x v sconf=$'cn\npc\npt\nwk\nmk\nca'; # io quitado
  err=4 # para default item pero no me va
  for v in fn $sconf; do
    eval local sv_n_$v sv_p_$v
    eval sv_n_$v=\$sv_$v
    eval sv_p_$v=\$sv_$v
  done
  while true; do
    x=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
        --title "Server settings" --default-item $err \
        --form "Server definition" 24 55 0 \
               "Fullfill this form." 1 1 '' 1 1 0 0 \
               "The friendly name is only for administration use." 2 1 '' 2 1 0 0 \
               "It is not exposed to the users" 3 1 '' 3 1 0 0 \
               "     Friendly name"  4 1 "${sv_n_fn:-my_server}"      4 20 ${sv_p_fn:-3}0 0 \
               "You can set an IP or a DNS name for the server" 6 1 ''  6 1 0 0 \
               "The best idea is to use a DNS server name" 7 1 ''        7 1 0 0 \
               "  Server name / IP"  8 1 "$sv_n_cn"                   8 20 30 0 \
               "Protocol (tcp/udp)"  9 1 "${sv_n_pc:-udp}"            9 20 4 3 \
               "              Port" 10 1 "${sv_n_pt:-1194}"          10 20 6 5 \
               "Do not use 192.168.1.0/24 as it is the usual" 12 1 '' 12 1 0 0 \
               "  home network" 13 1 '' 13 1 0 0 \
               "           Network" 14 1 "${sv_n_wk:-192.168.200.0}" 14 20 30 0 \
               "      Netmask bits" 15 1 "${sv_n_mk:-24}"            15 20 3 0 \

               #"  Fixed IPs offset" 10 1 '' 1 1 0 0 \
               #"           (min 6)" 11 1 "${sv_n_io:-6}" 11 20 6 5 
      )
    [ "$x" ] || return 1
    echo "$x" | grep -q '^$' && continue
    if [ "$sv_p_fn" ]; then
      read -d$'\1' -r sv_n_cn sv_n_pc sv_n_pt sv_n_wk sv_n_mk< <(echo "$x")
    else
      read -d$'\1' -r sv_n_fn sv_n_cn sv_n_pc sv_n_pt sv_n_wk sv_n_mk< <(echo "$x")
    fi
    [ "$sv_n_mk" ] || continue # miro el último
    sv_n_fn=$(clean $sv_n_fn)
    [ "$sv_n_fn" ] || return 1
    if [ ! "$sv_p_fn" ] && [ -d "$GESOVPN/server-$sv_n_fn" ]; then
      avisa "Server friendly name already exists" Error
      continue;
    fi
    if ! echo "$sv_n_cn" | grep -q -P '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$)' &&
       ! echo "$sv_n_cn" | grep -E '(([0-9]{1,3})\.){3}([0-9]{1,3}){1}' | grep -q -vE '25[6-9]|2[6-9][0-9]|[3-9][0-9][0-9]' ; then
      avisa "Enter vaid server name or IP" Error
      continue;
    fi
    if [ "$sv_n_pc" != tcp -a "$sv_n_pc" != udp ]; then
      avisa "Protocol error" Error
      continue;
    fi
    if [ "${sv_n_pt##[0-9]*}" ]; then
      avisa "Port error" Error
      continue;
    fi
    if ! echo "$sv_n_wk" | grep -E '(([0-9]{1,3})\.){3}([0-9]{1,3}){1}' | grep -q -vE '25[6-9]|2[6-9][0-9]|[3-9][0-9][0-9]' ; then
      avisa "Network error" Error
      continue;
    fi
    if [ "${sv_n_mk##[0-9]*}" ] || [ $sv_n_mk -lt 16 ] || [ $sv_n_mk -gt 27 ]; then
      avisa "Netmask error" Error
      continue;
    fi
    #if [ "${sv_n_io##[0-9]*}" ] || [ "$sv_n_io" -lt 6 ]; then
    #  dialog --keep-tite --stdout --backtitle "$BCKTIT" \
    #    --title "Error" \
    #    --msgbox "Offset error" 15 55
    #  err=1
    #  continue;
    #fi
    for f in $ls; do
      source $f/conf
      if [ "$sv_pc$sv_pt" == "$sv_n_pc$sv_n_pt" ] && [ "${f%%*server-}" != "$sv_n_fn" ]; then
        dialog --keep-tite --stdout --backtitle "$BCKTIT" \
        --yesno "There exist another server with $sv_n_pc / $sv_n_pt"$'\n'"To keep this config you must manually bind server to local IP" 15 55 \
        --title "Warning" &&
          break || err=9 && continue 2
      fi
    done
    break
  done
  if [ "$sv_p_fn" ]; then
    if [ "$sv_p_fn" != "$sv_n_fn" ]; then
      mv $GESOVPN/server-$sv_p_fn $GESOVPN/server-$sv_n_fn
      systemd
    fi
  fi
  if [ "$lc" ]; then
    ca_fn=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
            --title "CA" \
            --default-item "${sv_p_ca:----}" \
            --menu $'Select Certification Authority (CA) to use\nUsing an existent CA will share its clients' 10 50 0 \
            $(for f in $lc ; do
                source $f/conf
                echo ${f#$GESOVPN/ca-}
                echo $ca_cn
              done
             ) \
            "---" "New Certification Authority"
        )
    [ "$ca_fn" ] || return 1
    if [ "$ca_fn" != "---" ]; then
      source $GESOVPN/ca-$ca_fn/conf
    else
      ca_fn=''
      set_ca || return 1
    fi
  else
    set_ca || return 1
  fi
  sv_n_ca=$ca_fn
  mkdir $GESOVPN/server-$sv_n_fn/{,cld,block} 2>/dev/null
  for v in $sconf ; do
    eval vv=\$sv_n_$v
    echo sv_$v="'"$vv"'"
  done >$GESOVPN/server-$sv_n_fn/conf
  source $GESOVPN/server-$sv_n_fn/conf || 
    { rm -rf $GESOVPN/server-$sv_n_fn ; error "Config failed"; }
  if [ "$sv_p_ca$sv_p_cn" != "$sv_ca$sv_cn" ]; then
    source $GESOVPN/ca-$sv_n_ca/conf || error "Unable to read CA conf"
    mk_conf
    lee_pwca || return 1
    (openssl req -new -newkey rsa:2048 -keyout $GESOVPN/server-$sv_n_fn/key.pem -nodes \
                 -subj "$(haz_subj sv_cn ca_o ca_ou ca_l ca_st ca_c)" \
                 -out $GESOVPN/server-$sv_n_fn/req.pem >&2 &&
     echo -n "$pwca" | openssl ca -batch -in $GESOVPN/server-$sv_n_fn/req.pem  \
                -out $GESOVPN/server-$sv_n_fn/cert.pem -config $GESOVPN/openssl.cnf \
                -passin stdin >&2
    ) > >(espera "Generating Server cert") ||
     { rm -rf $GESOVPN/server-$sv_n_fn ;
      error "Error generating certificate"; }
  fi
  sv_fn=$sv_n_fn
  ls=$(ls -d $GESOVPN/server-* 2>/dev/null)
  pwca=''
  if [ ! -f "$sv_fn.conf" ]; then
    cat >$sv_fn.conf <<EOF
status --
log --
port --
proto --
dev --
ca --
cert --
key --
dh --
server --
crl-verify -- 'dir'
ifconfig-pool-persist --
client-config-dir --
mode server
tls-server
persist-key
persist-tun
compress lz4
keepalive 10 120
max-clients 60
EOF
  fi
  sed $sv_fn.conf -i \
    -e "s!^status .*!status /var/log/openvpn-status-$sv_fn.log!" \
    -e "s!^log .*!log /var/log/openvpn-$sv_fn.log!" \
    -e "s!^port .*!port $sv_pt!" \
    -e "s!^proto .*!proto $sv_pc!" \
    -e "s!^dev .*!dev tun_$sv_fn!" \
    -e "s!^ca .*!ca $wkd/$GESOVPN/ca-$sv_ca/ca.pem!" \
    -e "s!^cert .*!cert $wkd/$GESOVPN/server-$sv_fn/cert.pem!" \
    -e "s!^key .*!key $wkd/$GESOVPN/server-$sv_fn/key.pem!" \
    -e "s!^dh .*!dh $wkd/$GESOVPN/dh.pem!" \
    -e "s!^server .*!server $sv_wk $(cdr2mask $sv_mk)!" \
    -e "s!^ifconfig-pool-persist .*!ifconfig-pool-persist /var/log/ipp-$sv_fn.txt!" \
    -e "s!^client-config-dir .*!client-config-dir $wkd/$GESOVPN/server-$sv_fn/cld!" \
    -e "s!^crl-verify .*!crl-verify $wkd/$GESOVPN/server-$sv_fn/block 'dir'!"
  [ "$sv_p_fn" ] || { systemd ; start ; }
}

cons_ovpn() {
  local x d
  x=$(cat <<EOF
remote $sv_cn $sv_pt $sv_pc
nobind
tls-version-min 1.1
dev-type tun
dev tun_$sv_fn
verify-x509-name $sv_cn name
client
tls-client
compress lz4
<cert>
$(openssl x509 -in $GESOVPN/ca-$sv_ca/$cl_cn-crt.pem)
</cert>
<key>
$(cat $GESOVPN/ca-$sv_ca/$cl_cn-key.pem)
</key>
<ca>
$(openssl x509 -in $GESOVPN/ca-$sv_ca/ca.pem)
</ca>
EOF
)
  { d=$opw/$cl_cn.ovpn ; echo "$x" >$d ; } || 
  { d=./$cl_cn.ovpn ; echo "$x" >$d ; }
  avisa "The client file is in $d"$'\n\n'"Give it to the user and delete it"
}

set_cli () {
  local x nodes='' cl cn pwcl pwcl2 err;
  while true; do
    x="Client-$ca_cn"
    ll=$(grep "^V.*OU=${x:0:64}" $GESOVPN/ca-$sv_ca/index.txt | sed -n \
             -e 's/^V\s\+[0-9]\+Z\s\+\([0-9A-F]\+\)\s\+.*CN=\(.*\)/\1:!\2/p')
    if [ "$ll" ]; then
      cl=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
            --title "List of CA clients" --default-item "$cl" \
            --menu "Select a client to reconfigure" 15 55 0 \
            $(for f in $ll ; do
                echo ${f%%:!*}
                echo ${f#*:!}
              done
             ) \
            "---" "New client"
          )
      [ "$cl" ] || return 1
    else
      cl='---'
    fi
    if [ "$cl" == '---' ]; then
      err=''
      cn=''
      while true ; do
        x=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
             --title "New client" --insecure \
             --mixedform "Client setup" 15 55 0 \
                   "Use simple chars for Client name" 1 1 '' 1 1 0 0 0 \
                   "     Client Name" 2 1 "$cn" 2 19 30 0 0 \
                   "To avoid password, type ---" 4 1 "" 4 1 0 0 0 \
                   "Password (min 8)" 5 1 "" 5 19 30 0 1 \
                   "$err" 6 1 '' 6 1 0 0 0
           ) || return 1
        read -d$'\1' -r cn pwcl < <(echo "$x")
        cn=$(clean "$cn")
        [ ! "$cn" ] && continue
        if [ "$pwcl" != '---' ]; then
          [ "${#pwcl}" -ge 8 ] || continue
          pwcl2=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
                  --title "Password" --insecure \
                  --passwordbox "The same password" 15 55 ""
                 ) || return 1
          [ "$pwcl" == "$pwcl2" ] && break
          err="*** Passwords mismatch ***"
        else
          nodes='--nodes'
          break
        fi
      done
      cl_cn=$cn
      cl_ou="Client-$ca_cn"; cl_ou=${cl_ou:0:64}
      ca_fn=$sv_ca
      mk_conf
      lee_pwca || return 1
      (echo -n "$pwcl" | openssl req -new -newkey rsa:2048 -keyout $GESOVPN/ca-$ca_fn/$cn-key.pem \
                   -subj "$(haz_subj cl_cn ca_o cl_ou ca_l ca_st ca_c)" \
                   -out $GESOVPN/ca-$ca_fn/$cn-req.pem -passout stdin $nodes >&2 &&
       echo -n "$pwca" | openssl ca -batch -in $GESOVPN/ca-$ca_fn/$cn-req.pem  \
                    -out $GESOVPN/ca-$ca_fn/$cn-crt.pem -config $GESOVPN/openssl.cnf \
                    -passin stdin >&2 
      ) > >(espera "Generating Client cert") ||
       { rm -f $GESOVPN/ca-$ca_fn/$cn-{crt,key,req}.pem
        error "Error generating certificate"; }
      rm $GESOVPN/ca-$ca_fn/$cn-req.pem
      cl=$(openssl x509 -serial -noout -in $GESOVPN/ca-$ca_fn/$cn-crt.pem)
      cl=${cl#*=}
      cons_ovpn
      continue
    fi
    cl_cn=$(echo "$ll" | grep "$cl:!"); cl_cn=${cl_cn#*:!}
    while true; do
      ac=$(eval dialog --keep-tite --stdout --backtitle "'$BCKTIT'" \
              --title '"Action for the client"' \
              --menu '"Select an action for the client"' 15 55 0 \
                     '"Rebuid $cl_cn.ovpn" ""' \
                     $([ -f $GESOVPN/server-$sv_fn/block/$[16#$cl] ] || echo '"Block for this server" ""') \
                     $([ -f $GESOVPN/server-$sv_fn/block/$[16#$cl] ] && echo '"Unblock for this server" ""') \
                     $([ -f $GESOVPN/server-$sv_fn/cld/$cl_cn ] || echo '"Static IP" ""') \
                     $([ -f $GESOVPN/server-$sv_fn/cld/$cl_cn ] && echo '"Dinamic IP" ""') \
                     '"Change password" ""'
          )
      case ${ac:0:1} in
        R)  cons_ovpn ;;
        B)  touch $GESOVPN/server-$sv_fn/block/$[16#$cl]
            avisa "It will take effect when the client reconnects or when you restart server"
            ;;
        U)  rm -f $GESOVPN/server-$sv_fn/block/$[16#$cl] ;;
        C)  local f=$GESOVPN/ca-$ca_fn/$cl_cn-key.pem
            pwcl=$(lee_pw_pk $f "Current key password") || break
            pwcl2=$(lee_nw_pw)
            camb_pw_pk "$pwcl" "$pwcl2" "$f"
            cons_ovpn
            ;;
        S)  local ci i t b b2 p ib ib2 ip='' ip1
            ci=$(cd $GESOVPN/server-$sv_fn/cld
                 for f in * ; do
                   [ "$f" == "$cl_cn" ] || tr <$f '\n' ' '
                 done 2>/dev/null
                )
            t=$[1<<(32-$sv_mk)] # mitad de ips
            b=${sv_wk##*.}
            b2=${sv_wk%.$b}; b2=${b2##*.}
            p=${sv_wk%.$b2.$b}
            for ((i=$[b2*256+b+t/2]+2; i<b2*256+b+t-2; i+=4)); do
              ib2=$[i/256]
              ib=$[i%256]
              x=$p.$ib2.$ib
              if [ "$ci" == "${ci/$x/}" ]; then
                echo $x
                ip=$x
                ip1=$p.$ib2.$[ib-1]
                break;
              fi
            done
            if [ ! "$ip" ]; then
              avisa "Static pool exhausted, IP NOT defined"
              break
            fi
            echo "ifconfig-push $ip $ip1" >$GESOVPN/server-$sv_fn/cld/$cl_cn
            avisa "Static IP: $ip"
            ;;
        D)  rm -f $GESOVPN/server-$sv_fn/cld/$cl_cn;;
        *)  break;;
      esac
    done
  done
}


IFS=$'\n'
BCKTIT=${BCKTIT:-$(basename $0)}
GESOVPN=${GESOVPN:-gesOVPN}
[ "$EUID" -eq 0 ] ||
  { echo >&2 "You must be root."; exit 1; }
for pg in dialog openvpn openssl ; do
  command -v $pg >/dev/null 2>&1 ||
    { echo >&2 "I require '$pg' but it's not installed. Aborting."; exit 1; }
done
wkd=/etc/openvpn
opw=$PWD
[ -d $wkd ] ||
  error "Broken openvpn installation, /etc/openvpn does not exist"
cd $wkd

trap_exit () {
  [ "$gendh" ] && wait $gendh > >(espera $'Still generating DH params\nIt can take a lot of time')
  stty icrnl onlcr icanon echo
  echo Logs in $wkd/$log
}
trap trap_exit exit

if [ ! -d $GESOVPN ]; then
  dialog  --keep-tite --stdout --backtitle "$BCKTIT" \
    --title "Starting" \
    --yesno $'Welcome to the openvpn easy configurator\nNow you will setup your first server and your clients' 10 55 ||
   exit
  mkdir $GESOVPN
  chmod 700 $GESOVPN
  mkdir $GESOVPN/log
fi
log=$GESOVPN/log/$(date +%Y-%m-%d)-$$.log
exec 2>$log
if [ ! -s $GESOVPN/dh.pem ]; then
  nice openssl dhparam -out $GESOVPN/dh.pem 2048 & gendh=$!
  avisa $'Generating DH params in background\nThis is done only once, but can take a long time'
fi

while true; do 
  ls=$(ls -d $GESOVPN/server-* 2>/dev/null)
  lc=$(ls -d $GESOVPN/ca-* 2>/dev/null)
  if [ "$ls" ]; then
    fn=$(dialog --keep-tite --stdout --backtitle "$BCKTIT" \
            --title "Reconfigure server" \
            --menu "Select a server to reconfigure" 15 55 0 \
            $(for f in $ls ; do
                source $f/conf
                echo ${f#$GESOVPN/server-}
                echo $sv_cn-$sv_pc-$sv_pt
              done
             ) \
            "---" "New server"
        )
    [ "$fn" ] || exit
    sv_cn=''
    if [ "$fn" != "---" ] ; then
      sv_fn=$fn
      source $GESOVPN/server-$fn/conf || error "Config failed"
      source $GESOVPN/ca-$sv_ca/conf || error "Unable to read CA conf"
      ca_fn=$sv_ca
    fi
  fi
  if [ "$sv_cn" ]; then
    while true ; do
      ac=$(eval dialog --keep-tite --stdout --backtitle "'$BCKTIT'" \
              --title "'Action'" \
              --menu '"Select action" 15 55 0' \
                     $([ -f "$sv_fn.conf-disabled" ] && echo '"Enable server" ""') \
                     $([ -f "$sv_fn.conf" ] && echo '"Reconfigure server" "" "Start server" "" "Stop server" "" "Disable server" ""') \
                     '"Manage CA clients" ""' \
                     '"Change CA password" ""')
      case ${ac:0:3} in
        Man) set_cli ;;
        Rec) set_srv ;;
        Sta) start ;;
        Sto) stop ;;
        Ena) mv -i $sv_fn.conf-disabled $sv_fn.conf </dev/null
             systemd ;;
        Dis) stop
             mv $sv_fn.conf $sv_fn.conf-disabled
             systemd ;;
        Cha) lee_pwca || break;
             pwca2=$(lee_nw_pw) || break;
             camb_pw_pk "$pwca" "$pwca2" "$GESOVPN/ca-$ca_fn/key.pem"
             pwca=$pwca2
             ;;
        *) break;;
      esac
    done
  else
    if ! set_srv ; then
      [ "$ls" ] && continue
      exit
    fi
    set_cli
  fi
done
# TODO ver de quitar el err de set_svr
