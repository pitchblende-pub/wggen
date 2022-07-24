#!/bin/bash
# wges.sh WireGuard Easy Setup

Peers=10 # 設定するクライアントの数。1〜9999の範囲。
ServerPort=51820 # サーバー側WireGuardが使用する実ポート
Endpoint=example.ddns.jp:51820 # 外部から見た場合のサーバーアドレスとポート番号
EthernetInterface='' # サーバーから外部にアクセスするための実インターフェイス名（空欄の場合は自動取得を試向）
DNS='1.1.1.1, 2606:4700:4700::1111' # トンネル開通後に参照するネームサーバー（デフォルトはCloudflare）

# クライアントがどこ向けのアクセスをトンネルに流す（かつ受け入れる）かの設定
# $iはクライアント番号、$IPv6Prefixは生成した48bitプレフィックスに置き換えられる。
# 192.〜の部分は環境に合わせて修正
ClientAllowedIPs='192.168.X.X/24' # サーバー側LAN向けアクセスのみをトンネルする場合
#ClientAllowedIPs='192.168.X.X/24, 10.0.0.0/16, $IPv6Prefix::/96' # 上に加えて、Wireguardでつながる全コンピューターを対象
#ClientAllowedIPs='0.0.0.0/0, ::/0' # 全アクセスをトンネルさせてサーバー経由にする場合

#### 多くの場合、ここより下の行は変更不要 ####

ServerConfigFile=wg0.conf # /etc/wireguardに置くファイルの名前

# トンネルとして使う仮想インターフェイスのアドレス
ServerWgAddress='10.0.100.1/16, $IPv6Prefix::a000/96'
ClientWgAddress='10.0.$((i/100)).$((i%100))/16, $IPv6Prefix::$i/96'

# サーバーがどこ向けのアクセスをトンネルに流す（または受け入れる）かの設定
ServerAllowedIPs='10.0.$((i/100)).$((i%100))/32, $IPv6Prefix::$i/128'

UsePSK=true # 事前共有鍵を使用するか否か(true/false)
OutputDir='wges-output' # 設定ファイルの出力先。絶対パスまたは本スクリプトからの相対パス。
###################################################################################################
umask=077
cd `dirname $0` || exit 1
if [ ! -d ${OutputDir}/keys ]; then
	mkdir -p ${OutputDir}/keys || exit 1
fi
cd $OutputDir || exit 1

if [ -z $EthernetInterface ]; then
	# 定義されていない場合はシステムから取得
	EthernetInterface=$(for d in `find /sys/devices -name net | grep -m1 -v virtual`; do ls $d/; done)
	if [ -z $EthernetInterface ]; then
		echo "EthernetInterfaceを指定してください。"
		exit 1
	fi
fi

if [ ! -f keys/server.txt ]; then
	# RFC4139に従いIPv6プレフィックスを生成
        IPv6Prefix=$(echo $(date +%s%N)$(cat /etc/machine-id)|sha512sum --tag|sed -e 's/.*\(..\)\(....\)\(...\)$/fd\1:\2:\3/g')
        echo $(wg genkey |tee keys/server.txt|wg pubkey)$'\n'${IPv6Prefix} >> keys/server.txt || exit 1
fi

for i in $(seq $Peers) ; do
        base=$(printf %04d $i)
        if [ ! -f keys/$base.txt ]; then
		echo $(wg genkey |tee keys/$base.txt|wg pubkey;wg genpsk) |tr ' ' '\n' >> keys/$base.txt || exit 1
        fi
done

IFS=$'\n'
keys=($(cat keys/server.txt))
ServerPrivatekey=${keys[0]}
ServerPublickey=${keys[1]}
IPv6Prefix=${keys[2]}

### サーバー設定ファイルの[Interface]部分を出力
# クライアント→LAN内はNATでアクセス、クライアントへは他クライアント含め自由にアクセス可という設定。
cat > ${ServerConfigFile} <<EOF1|| exit 1
[Interface]
Address = $(eval echo $ServerWgAddress)
PostUp   = iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $EthernetInterface -j MASQUERADE; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $EthernetInterface -j MASQUERADE
PostDown = iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $EthernetInterface -j MASQUERADE; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $EthernetInterface -j MASQUERADE
ListenPort = $ServerPort
PrivateKey = $ServerPrivatekey
EOF1
### ここまで

#ヒアドキュメント使用のため、行頭のタブをスペースに変換しないこと
for i in $(seq $Peers) ; do
	base=$(printf %04d $i)
	keys=($(cat keys/$base.txt)) || exit 1
	ClientPrivatekey=${keys[0]}
	ClientPublickey=${keys[1]}
	PSKkey=${keys[2]}

	if "$UsePSK"; then
		pskoutput="PresharedKey = $PSKkey"
	else
		pskoutput="#PresharedKey = $PSKkey"
	fi

	### Peer設定ファイルを出力
	cat <<-EOF2 > c${base}.conf || exit 1
	[Interface]
	PrivateKey = $ClientPrivatekey
	Address = $(eval echo $ClientWgAddress)
	DNS = $DNS

	[Peer]
	PublicKey = $ServerPublickey
	Endpoint = $Endpoint
	AllowedIPs = $(eval echo $ClientAllowedIPs)
	$pskoutput
	EOF2
	### ここまで

	### サーバー設定ファイルの各[Peer]部分を出力
	cat <<-EOF3 >> ${ServerConfigFile}|| exit 1

	[Peer] #$i
	PublicKey = $ClientPublickey
	AllowedIPs = $(eval echo $ServerAllowedIPs)
	$pskoutput
	EOF3
	### ここまで

	# qrencodeコマンドがある場合はQRコードを生成
	if [ -n "$(command -v qrencode)" ]; then
		qrencode -t ANSIUTF8i -r c${base}.conf -o qr${base}.txt || exit 1
		qrencode -t PNG -r c${base}.conf -o qr${base}.png || exit 1
	fi
done
