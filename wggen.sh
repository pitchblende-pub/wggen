#!/bin/bash

Peers=10 # 設定するクライアントの数。1〜9999の範囲。
ServerConfigFile=wg0.conf # /etc/wireguardに置くファイルの名前
ServerPort=51820 # Wireguardが使用する実ポート
Endpoint=example.ddns.jp:51820 # 外部から見た場合のサーバーアドレスとポート番号

# 次の2行は、他のマシンをサーバーにする場合は必ず手動で設定
#EthernetInterface=eth0 # サーバーから外部にアクセスするための実インターフェイス
#DNS=192.168.1.1 # サーバーが参照するネームサーバー

#トンネルとして使う仮想インターフェイスのアドレス($iはクライアント番号で置き換えられる。)
ServerWgAddress='10.0.100.1/16, fdfd:abcd:1::a000/96'
ClientWgAddress='10.0.$((i/100)).$((i%100))/16, fdfd:abcd:1::$i/96'

# 仮想インターフェイスにどの宛先のパケットを送るかの選択($iはpeer番号で置き換えられる。)
ServerAllowedIPs='10.0.$((i/100)).$((i%100))/32, fdfd:abcd:1::$i/128'
ClientAllowedIPs='10.0.0.0/16, fdfd:abcd:1::0/96, 192.168.1.0/24' # LAN内向けアクセスのみをトンネルさせる場合（192.168.1.0/24は実行環境に合わせること）
#ClientAllowedIPs='0.0.0.0/0,::0' # 全アクセスをトンネルさせる場合

GenPSK=true #事前共有鍵を生成するか否か
OutputDir='output' # 設定ファイルの出力先。絶対パスまたは本スクリプトからの相対パス。

cd `dirname $0` || exit 1
IFS=$'\n'
if [ -z $EthernetInterface ]; then
	EthernetInterface=$(for d in `find /sys/devices -name net | grep -m1 -v virtual`; do ls $d/; done)
	if [ -z $EthernetInterface ]; then
		echo "EthernetInterfaceを指定してください。"
		exit 1
	fi
fi

if [ -z $DNS ]; then
	DNS=$(resolvectl dns $EthernetInterface |sed -ne 's/.\+:[\t ]\+\([0-9a-f.:]\+\)[\t ]*$/\1/p')
	if [ -z $DNS ]; then
		echo "DNSを指定してください。"
		exit 1
	fi
fi

if [ ! -d ${OutputDir}/keys ]; then
	mkdir -p ${OutputDir}/keys || exit 1
fi

if [ ! -f ${OutputDir}/keys/server.txt ]; then
	pubkey=$(wg genkey |tee ${OutputDir}/keys/server.txt|wg pubkey)
	echo $pubkey >> ${OutputDir}/keys/server.txt || exit 1
fi

for i in $(seq  $Peers) ; do
	base=$(printf %04d $i)
	if [ ! -f ${OutputDir}/keys/$base.txt ]; then
		pubkey=$(wg genkey |tee ${OutputDir}/keys/$base.txt|wg pubkey)
		if "${GenPSK}"; then
			psk=$(wg genpsk)
			echo ${pubkey}$'\n'${psk}>> ${OutputDir}/keys/$base.txt || exit 1
		fi
        fi
done

keys=($(cat ${OutputDir}/keys/server.txt))
ServerPrivatekey=${keys[0]}
ServerPublickey=${keys[1]}

### サーバー設定ファイルの[Interface]部分を出力
# クライアント→LAN内はNATでアクセス、クライアントへは他クライアント含め自由にアクセス可という設定。
cat > ${OutputDir}/${ServerConfigFile} <<EOF1|| exit 1
[Interface]
Address = $ServerWgAddress
PostUp   = iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $EthernetInterface -j MASQUERADE; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $EthernetInterface -j MASQUERADE
PostDown = iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $EthernetInterface -j MASQUERADE; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $EthernetInterface -j MASQUERADE
ListenPort = $ServerPort
PrivateKey = $ServerPrivatekey
EOF1
### ここまで

for i in $(seq $Peers) ; do
	base=$(printf %04d $i)
	keys=($(cat ${OutputDir}/keys/$base.txt)) || exit 1
	ClientPrivatekey=${keys[0]}
	ClientPublickey=${keys[1]}
	if [ -z ${keys[2]} ]; then
		psk="#TBDel"
	else
		psk="PresharedKey = ${keys[2]}"
	fi

	### Peer設定ファイルを出力
	cat <<-EOF2 |sed -e '/^#TBDel/d' > ${OutputDir}/c${base}.conf || exit 1
	[Interface]
	PrivateKey = $ClientPrivatekey
	Address = $(eval echo $ClientWgAddress)
	DNS = $DNS

	[Peer]
	PublicKey = $ServerPublickey
	Endpoint = $Endpoint
	AllowedIPs = $ClientAllowedIPs
	$psk
	EOF2
	### ここまで

	### サーバー設定ファイルの各[Peer]部分を出力
	cat <<-EOF3 |sed -e '/^#TBDel/d' >> ${OutputDir}/${ServerConfigFile}|| exit 1

	[Peer] #$i
	PublicKey = $ClientPublickey
	AllowedIPs = $(eval echo $ServerAllowedIPs)
	$psk
	EOF3
	### ここまで

	# qrencodeコマンドがある場合はQRコードを生成
	if [ -n "$(command -v qrencode)" ]; then
		qrencode -t ANSIUTF8i -r ${OutputDir}/c${base}.conf -o ${OutputDir}/qr${base}.txt || exit 1
		qrencode -t PNG -r ${OutputDir}/c${base}.conf -o ${OutputDir}/qr${base}.png || exit 1
	fi
done
