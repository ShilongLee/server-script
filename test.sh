###
 # @Author: lishilong
 # @Date: 2025-03-14 10:33:20
 # @LastEditors: lishilong
 # @LastEditTime: 2025-03-20 17:06:51
 # @Desc: 本地启动服务器
### 
#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

echo "========================================"
echo "       服务器环境配置和启动脚本        "
echo "========================================"

# 更新软件包索引（只需执行一次）
echo "更新软件包索引..."
apt update

###################
# Docker 安装部分 #
###################

echo "========================================"
echo "第一步：检查和安装 Docker"
echo "========================================"

# 检查 Docker 是否已安装
if command -v docker >/dev/null 2>&1; then
    echo "√ Docker 已安装，版本信息："
    docker --version
    echo "跳过 Docker 安装步骤..."
else
    echo "× Docker 未安装，开始安装过程..."

    # 安装必要的依赖包
    echo "安装必要的依赖包..."
    apt install apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release -y

    # 添加 Docker 的官方 GPG 密钥
    echo "添加 Docker 的官方 GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # 设置 Docker 仓库
    echo "设置 Docker 仓库..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 再次更新软件包索引（添加新仓库后需要）
    echo "更新软件包索引..."
    apt update

    # 安装 Docker Engine
    echo "安装 Docker Engine..."
    apt install docker-ce docker-ce-cli containerd.io -y

    # 验证 Docker 是否安装成功
    echo "验证 Docker 是否安装成功..."
    if docker run hello-world; then
        echo "√ Docker 安装成功！"
    else
        echo "× Docker 安装可能出现问题，请检查上述错误信息。"
        exit 1
    fi

    # 将当前用户添加到 docker 用户组
    echo "将当前用户添加到 docker 用户组..."
    usermod -aG docker $SUDO_USER || echo "警告：无法将用户添加到 docker 组，可能需要手动执行: sudo usermod -aG docker \$USER"

    # 设置 Docker 开机自启
    echo "设置 Docker 开机自启..."
    systemctl enable docker

    echo "Docker 安装和配置完成！"
    echo "请注意：您可能需要注销并重新登录，或重启系统，以使用户组更改生效。"
fi

#################
# Git 安装部分 #
#################

echo "========================================"
echo "第二步：检查和安装 Git"
echo "========================================"

# 检查 Git 是否已安装
if command -v git >/dev/null 2>&1; then
    echo "√ Git 已安装，版本信息："
    git --version
    echo "跳过 Git 安装步骤..."
else
    echo "× Git 未安装，开始安装过程..."

    # 安装 Git
    echo "安装 Git..."
    apt install git -y

    # 验证 Git 是否安装成功
    if git --version > /dev/null 2>&1; then
        echo "√ Git 安装成功！版本信息："
        git --version
    else
        echo "× Git 安装可能出现问题，请检查上述错误信息。"
        exit 1
    fi

    echo "Git 安装完成！"
fi

# 获取用户输入的SERVER_BRANCH值（提前获取分支名，以便在下载项目或更新项目时使用）
read -p "请输入需要启动的分支 (默认develop): " new_branch
new_branch=${new_branch:-develop}  # 如果用户未输入，则默认为develop

# 获取本地IP地址
local_ip=$(hostname -I | awk '{print $1}')
if [ -z "$local_ip" ]; then
    echo "警告：无法获取本地IP地址"
    read -p "请手动输入IP地址: " local_ip
fi

echo "获取到本地IP地址: $local_ip"

#################
# 项目下载部分 #
#################

echo "========================================"
echo "第三步：下载或更新项目代码"
echo "========================================"

# 检查项目是否已存在
if [ ! -d "slg_compose" ]; then
    echo "开始下载项目..."

    # 下载项目
    git clone http://tygit.tuyoo.com/sanguo/tools/slg_compose.git

    # 验证下载是否成功
    if [ -d "slg_compose" ]; then
        echo "√ 项目下载成功！"
        # 切换到指定分支
        cd slg_compose
        git checkout master
        cd ..
        echo "√ 已切换到 master 分支"
    else
        echo "× 项目下载失败，请检查上述错误信息。"
        exit 1
    fi
else
    echo "√ 项目目录已存在，正在更新代码..."
    
    # 进入项目目录
    cd slg_compose
    
    # 确保工作区干净
    git reset --hard
    
    # 切换到指定分支并拉取最新代码
    git fetch --all
    git checkout master
    git pull --force
    
    echo "√ 已切换到 master 分支并更新到最新代码"
    
    # 返回原目录
    cd ..
fi

####################
# 环境配置文件修改 #
####################

echo "========================================"
echo "第四步：配置环境变量"
echo "========================================"

# 获取.env文件的路径
ENV_FILE="slg_compose/docker/.env"

# 检查.env文件是否存在
if [ ! -f "$ENV_FILE" ]; then
    echo "× 错误：未找到.env文件（$ENV_FILE）"
    exit 1
fi

# 替换SERVER_BRANCH值
sed -i "s|^SERVER_BRANCH=.*$|SERVER_BRANCH=\"$new_branch\"|" "$ENV_FILE"

# 取消LOCAL_HOST的注释并替换值
if grep -q "^LOCAL_HOST=" "$ENV_FILE"; then
    # 如果LOCAL_HOST已经取消注释，直接替换值
    sed -i "s|^LOCAL_HOST=.*$|LOCAL_HOST=\"$local_ip\"|" "$ENV_FILE"
elif grep -q "^# LOCAL_HOST=" "$ENV_FILE"; then
    # 如果LOCAL_HOST被注释，取消注释并替换值
    sed -i "s|^# LOCAL_HOST=.*$|LOCAL_HOST=\"$local_ip\"|" "$ENV_FILE"
else
    # 如果LOCAL_HOST不存在，添加它
    echo "LOCAL_HOST=\"$local_ip\"" >> "$ENV_FILE"
fi

echo "√ 环境配置更新完成！"
echo "  * SERVER_BRANCH=\"$new_branch\""
echo "  * LOCAL_HOST=\"$local_ip\""

####################
# ZooKeeper配置修改 #
####################

echo "========================================"
echo "第五步：更新ZooKeeper配置"
echo "========================================"

# 获取ZooKeeper配置文件的路径
ZK_DIR="slg_compose/volume/zookeeper/conf"
ZK_FILE="$ZK_DIR/slg.zk"

# 确保目录存在
mkdir -p "$ZK_DIR"

# 检查ZooKeeper配置文件是否存在
if [ ! -f "$ZK_FILE" ]; then
    echo "ZooKeeper配置文件不存在，正在创建..."
    
    # 创建基本的ZooKeeper配置文件
    cat > "$ZK_FILE" << EOF
/slg/server/cluster/global/machine={"host":"$local_ip","port":8082}
/slg/server/cluster/global/machine/list=[{"host":"$local_ip","port":8082}]
/slg/server/cluster/games-connector/machine/list=[{"host":"$local_ip","port":8081}]
/slg/server/cluster/game-service/machine/list=[{"host":"$local_ip","port":8080}]
EOF
    echo "√ ZooKeeper配置文件创建成功！"
else
    # 替换文件中的IP地址
    echo "正在更新ZooKeeper配置文件..."
    sed -i "s/172.16.8.165/$local_ip/g" "$ZK_FILE"
    sed -i "s/LS_V1/S3_V1/g" "$ZK_FILE"
    echo "√ ZooKeeper配置更新完成！"
    echo "  * 已将IP地址从172.16.8.165更新为$local_ip"
fi

# 创建ZooKeeper命令执行脚本
echo "正在创建ZooKeeper命令执行脚本..."
ZK_SCRIPT="$ZK_DIR/slg.sh"
cat > "$ZK_SCRIPT" << EOF
/apache-zookeeper-3.7.2-bin/bin/zkCli.sh -server localhost:2181 < /data/slg.zk
EOF

# 赋予执行权限
chmod +x "$ZK_SCRIPT"
echo "√ ZooKeeper命令脚本创建成功：$ZK_SCRIPT"

####################
# 启动服务 #
####################

echo "========================================"
echo "第六步：登录Docker仓库并启动服务"
echo "========================================"

# 进入docker目录
cd slg_compose/docker

echo "登录Docker仓库..."
if docker login harbor.ops.tuyoops.com -u 'robot$sanguoxj-187+sanguoxj-read' --password 'zs11x7CZA8agULeiaz5r8I7zvYgO51hF'; then
    echo "√ Docker仓库登录成功"
else
    echo "× Docker仓库登录失败，请检查凭据"
    exit 1
fi

echo "停止现有服务..."
docker compose stop

echo "拉取最新镜像..."
docker compose pull

echo "启动服务..."
docker compose up -d

# 等待ZooKeeper容器启动
echo "等待ZooKeeper容器启动..."
sleep 10

echo "配置ZooKeeper..."
if docker exec zookeeper_container /bin/bash /data/slg.sh; then
    echo "√ ZooKeeper配置成功"
else
    echo "× ZooKeeper配置可能失败，请检查容器名称"
    echo "  您可能需要手动执行: docker exec zookeeper_container /bin/bash /data/slg.sh"
fi

echo "========================================"
echo "服务启动完成！您可以通过 http://$local_ip:8080 访问游戏服务器："
echo "========================================"