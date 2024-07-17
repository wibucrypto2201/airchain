Version="1.0.1"

# 定义要检查的包列表
packages=(
    jq
    curl
    wget
    build-essential
    git
    make
    clang
    pkg-config
    libssl-dev
)

# 检查并安装每个包
function init() {
    for pkg in "${packages[@]}"; do
    if dpkg-query -W "$pkg" >/dev/null 2>&1; then
        echo "$pkg installed,skip"
    else
        echo "install  $pkg..."
        sudo apt update
        sudo apt install -y "$pkg"
    fi
done
    if command -v go >/dev/null 2>&1; then
    echo "go 已安装，跳过安装步骤。"
else
    echo "下载并安装 Go..."
    wget -c https://golang.org/dl/go1.22.4.linux-amd64.tar.gz -O - | sudo tar -xz -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc

fi
}



ALL_SATEA_VARS="name,passwd"


name={{SATEA_VARS_name}}

passwd={{SATEA_VARS_passwd}}


##显示需要接收的变量
function VadVars(){
     echo "$ALL_SATEA_VARS"
}

#手动模式下 解析并填入变量的函数
function Manual() {
   >.env.sh
   chmod +x .env.sh
   for i in `echo $ALL_SATEA_VARS | tr ',' '\n' `;do

   i_split=`echo $i |tr -d "{" | tr -d "}"`

   read  -p "$i_split ="  i_split_vars

   echo "$i_split=$i_split_vars" >>.env.sh

  done
}
function install_node(){
PATH=$PATH:/usr/local/go/bin
# 验证安装后的 Go 版本
echo "当前 Go 版本："
go version

 cd $HOME
    git clone https://github.com/airchains-network/wasm-station.git
    git clone https://github.com/airchains-network/tracks.git
    cd wasm-station
    go mod tidy
    /bin/bash ./scripts/local-setup.sh

    sudo tee <<EOF >/dev/null /etc/systemd/system/wasmstationd.service
[Unit]
Description=wasmstationd
After=network.target

[Service]
User=$USER
ExecStart=$HOME/wasm-station/build/wasmstationd start --api.enable
Restart=always
RestartSec=3
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload && \
    sudo systemctl enable wasmstationd && \
    sudo systemctl start wasmstationd
    
    cd
wget https://github.com/airchains-network/tracks/releases/download/v0.0.2/eigenlayer
sudo chmod +x eigenlayer
sudo mv eigenlayer /usr/local/bin/eigenlayer

KEY_FILE="$HOME/.eigenlayer/operator_keys/$name.ecdsa.key.json"

if [ -f "$KEY_FILE" ]; then
    echo "文件 $KEY_FILE 已经存在，删除文件"
    rm -f "$KEY_FILE"

    echo "$passwd" | eigenlayer operator keys create --key-type ecdsa --insecure $name 2>&1 | tee $HOME/eigenlayer.txt
else
    echo "文件 $KEY_FILE 不存在，执行创建密钥操作"

    echo "$passwd" | eigenlayer operator keys create --key-type ecdsa --insecure $name 2>&1 | tee $HOME/eigenlayer.txt
fi
cp $HOME/eigenlayer.txt $HOME/eigenlayer.txt.bk
sudo rm -rf ~/.tracks
cd $HOME/tracks
go mod tidy
#!/bin/bash

Public_Key=$(cat $HOME/eigenlayer.txt.bk |grep Public |awk '{print $4}')


go run cmd/main.go init \
    --daRpc "disperser-holesky.eigenda.xyz" \
    --daKey "$Public_Key" \
    --daType "eigen" \
    --moniker "$name" \
    --stationRpc "http://127.0.0.1:26657" \
    --stationAPI "http://127.0.0.1:1317" \
    --stationType "wasm"

go run cmd/main.go keys junction --accountName $name --accountPath $HOME/.tracks/junction-accounts/keys

go run cmd/main.go prover v1WASM
read -p "是否已经领水完毕要继续执行？(yes/no): " choice

if [[ "$choice" != "yes" ]]; then
    echo "脚本已终止。"
    exit 0
fi
echo "继续执行脚本..."

echo $bootstrapNode
CONFIG_PATH="$HOME/.tracks/config/sequencer.toml"
WALLET_PATH="$HOME/.tracks/junction-accounts/keys/$name.wallet.json"

# 从配置文件中提取 nodeid
NODE_ID=$(grep 'node_id =' $CONFIG_PATH | awk -F'"' '{print $2}')

# 从钱包文件中提取 air 开头的钱包地址
AIR_ADDRESS=$(jq -r '.address' $WALLET_PATH)

# 获取本机 IP 地址
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 定义 JSON RPC URL 和其他参数
JSON_RPC="https://airchains-testnet-rpc.itrocket.net/"
INFO="EVM Track"
TRACKS="air_address"
BOOTSTRAP_NODE="/ip4/$LOCAL_IP/tcp/2300/p2p/$NODE_ID"

# 运行 tracks create-station 命令
create_station_cmd="go run cmd/main.go create-station \
    --accountName $name \
    --accountPath $HOME/.tracks/junction-accounts/keys \
    --jsonRPC \"https://airchains-testnet-rpc.itrocket.net/\" \
    --info \"WASM Track\" \
    --tracks \"$AIR_ADDRESS\" \
    --bootstrapNode \"/ip4/$LOCAL_IP/tcp/2300/p2p/$NODE_ID\""

echo "Running command:"
echo "$create_station_cmd"

# 执行命令
eval "$create_station_cmd"
sudo tee /etc/systemd/system/stationd.service > /dev/null << EOF
[Unit]
Description=station track service
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/tracks/
ExecStart=$(which go) run cmd/main.go start
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable stationd
sudo systemctl restart stationd
}



function wasmstationd_log(){
    journalctl -u wasmstationd -f
}
function evm_log(){
    journalctl -u evm -f
}
function stationd_log(){
    journalctl -u stationd -f
}
function private_key(){
    #evmos私钥#
    cd $HOME/data/airchains/evm-station/ &&  /bin/bash ./scripts/local-keys.sh
    #airchain助记词#
    cat $HOME/.tracks/junction-accounts/keys/$name.wallet.json

}
function addr_key(){
    cat $HOME/.tracks/junction-accounts/keys/$name.wallet.json
}
function restart(){
sudo systemctl restart stationd.service
sudo systemctl restart wasmstationd.service
}

function clean(){
sudo rm -rf data
sudo rm -rf .evmosd
sudo rm -rf .tracks
sudo rm -rf wasm-station
sudo rm -rf tracks
sudo systemctl stop wasmstationd.service
sudo systemctl stop stationd.service
sudo systemctl disable wasmstationd.service
sudo systemctl disable stationd.service
sudo pkill -9 wasmstationd
sudo pkill -9 stationd
sudo journalctl --vacuum-time=1s

}
function tx_node(){
    cd
addr=$($HOME/wasm-station/build/wasmstationd keys show node --keyring-backend test -a)
sudo tee spam.sh > /dev/null << EOF
#!/bin/bash

while true; do
  $HOME/wasm-station/build/wasmstationd tx bank send node ${addr} 1stake --from node --chain-id station-1 --keyring-backend test -y 
  sleep 6  
done
EOF
nohup bash spam.sh &
}




function About() {
echo '   _____    ___     ______   ______   ___
  / ___/   /   |   /_  __/  / ____/  /   |
  \__ \   / /| |    / /    / __/    / /| |
 ___/ /  / ___ |   / /    / /___   / ___ |
/____/  /_/  |_|  /_/    /_____/  /_/  |_|'

echo
echo -e "\xF0\x9F\x9A\x80 Satea Node Installer
Website: https://www.satea.io/
Twitter: https://x.com/SateaLabs
Discord: https://discord.com/invite/satea
Gitbook: https://satea.gitbook.io/satea
Version: $Version
Introduction: Satea is a DePINFI aggregator dedicated to breaking down the traditional barriers that limits access to computing resources.  "
echo""
}





case $1 in

install)

  if [ "$2" = "--auto" ]
  then
     echo "-> Automatic mode, please ensure that ALL SATEA_VARS(`VadVars`) have been replaced !"
          sleep 3

     #这里使用自动模式下的 安装 函数
     install

    else
      echo "Unrecognized variable(`VadVars`) being replaced, manual mode"

      #手动模式 使用Manual 获取用户输入的变量

      Manual      #获取用户输入的变量
      . .env.sh   #导入变量

      #其他安装函数
      install_node
    fi
  ;;
tx_node)
tx_node
  ;;
init)
init
  ;;
vars)
VadVars
  ;;
clean)
clean
  ;;
restart)
restart
  ;;
addr_key)
addr_key
;;
wasmstationd_log)
wasmstationd_log
  ;;
stationd_log)
stationd_log
  ;;

**)

 #定义帮助信息 例子
 About
  echo "Flag:
  install         Install Hubble with manual mode,  If carrying the --auto parameter, start Automatic mode
  init            Install Dependent packages
  restart              restart the service
  tx_node              start tx
  addr_key             show your key
  wasmstationd_log     how the logs of the was service
  stationd_log         how the logs of the stationd service
  clean                Remove the Hubble from your server"
  ;;
esac
