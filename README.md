# wggen
 Wireguard Config File Generator

## 概要

Wireguardの設定がいろいろと面倒なので、設定ファイルを自動生成するbashスクリプトを作りました。似たものは複数ありましたが、自分の用途に合うものが無く自作しました。実行すると、スクリプトを置いた場所の直下のoutputディレクトリ（場所は変更可能）に各種設定ファイルを生成します。通信に必要な公開鍵・秘密鍵なども生成します。
1. サーバー側設定ファイル
> wg0.conf
2. クライアント側設定ファイル
> c0001.conf, c0002.conf, c0003.conf, …
3. クライアント側設定ファイルをQRコード化したテキスト・画像ファイル（qrencodeがインストールされている場合）
> qr0001.txt, qr0001.png, qr0002.txt, qr0002.png, …
## 注意点
Wireguardではトンネリング両端のホストの扱いに差はありませんが、本スクリプトは、1つのサーバーに多数のクライアントが接続するようなVPNシステムの考え方を前提としています。また設定ファイルを生成するだけなので、それらを適切な場所に設置したり、外部からアクセスするためのDDNSやNAT等の設定、Wireguardのインストール・起動・自動起動等は別に行う必要があります。

## 使用法
適当なディレクトリに本スクリプトを置き、***後記の「設定が必要な変数一覧」を編集し***実行してください。outputディレクトリ下にwg0.confが生成されるので、これを/etc/wireguard/にコピーし
> wq-quick up wg0

を実行することにより、Wireguardが起動します。一方クライアント側には、c0001.conf等のファイルをインストールしてください。linuxならばwg0.confに名前を変えて/etc/wireguardにコピー、スマホではqr0001.txtやqr0001.pngを、Wireguardアプリ内のカメラで読み込ませてください。

その他の設定に問題がなければ、トンネリングを利用した通信が可能になります。通信を確認したらサーバー側で
> sudo systemctl start wg-quick@wg0

を実行し自動起動を設定します。

## 設定が必要な変数一覧
#### Peers
サーバーにぶら下がるクライアント数。9999まで対応。
#### ServerConfigFile
サーバーの設定ファイル。/etc/wireguardにコピーして使用。
#### ServerPort
サーバーのWireguardが使用する実ポート。
#### Endpoint
外部からアクセスする時に使用するサーバー名・ポート番号。
#### EthernetInterface
サーバーがトンネルされて届いたアクセスを他のコンピューターにつなぐ場合に使用するインターフェイス名。
#### DNS
トンネル接続後にクライアント側が使用するネームサーバー。
#### ServerWgAddress, ClientWgAddress
それぞれ、サーバー側・クライアント側の仮想インターフェイスのIPアドレス。$iをクライアント番号として記述可能。
#### ServerAllowedIPs, ClientAllowedIPs
それぞれ、サーバー側・クライアント側において、どの宛先向けのアクセスをトンネリングに流すかを指定する変数。デフォルトの設定では、サーバー側は相手のクライアント向けアクセスのみをトンネル。クライアント側は、サーバー、サーバーにつながる全クライアント、サーバーがつながっているLANである192.168.1.0/64向けをトンネル。***（最後のLANアドレスは環境に従って要修正。）***
#### UsePSK
trueの場合は事前共有鍵を生成。
#### OutputDir
生成したファイルの出力先を、絶対パスまたは本スクリプトからの相対パスで指定。

## 補足
スクリプトを実行すると、$OutputDir/keys下にサーバー・各クライアントの秘密鍵・公開鍵・事前共有鍵を記述したファイルが生成され、その後にそれらのファイルを読んで$OutputDirに設定ファイルが作られるという2段階のプロセスが発生します。スクリプトの実行が2度目以降の場合、1段階目で作られたファイルが残っている場合は再利用され、存在しないもののみ生成されます。そのため、鍵を作り直す場合はkeys以下のファイルを削除してから実行してください。鍵はそのままでその他の設定を変更したい場合は削除せずに実行してください。 例えばサーバーの設定のみを修正するときには、keys以下のファイルをそのままにしておくことにより、クライアント全ての設定ファイルをインストールし直すようなことが避けられます。
<br>
仮想インターフェイスのアドレスは、サーバーが192.168.100.1/16(IPv6 fdfd:abcd:1::クライアント番号/96)、クライアントが192.168.クライアント番号の上2桁.下2桁(IPv6 fdfd:abcd:1::クライアント番号)に設定されます。これを変えるにはServer(Client)WgAddressを修正してください。
