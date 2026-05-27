# 先让环境变量生效（仅需一次，新终端会自动加载）
source ~/.bashrc

# 进入项目目录
cd ~/madl-dvt

# 构建
stack build

# 运行死锁检测
stack exec -- dlockdetect -x twoagents2

# 对 .madl 文件分析  一个死锁的demo
stack exec -- dlockdetect -f examples/MaDL/fig15.madl

# 最大的有死锁+活锁的工业级模型（308 队列）
stack exec -- dlockdetect -f examples/MaDL/ligero/model00.madl

# 最大的无死锁拓扑（80 队列 TornadoNoC）
stack exec -- dlockdetect -f examples/MaDL/TornadoNoC/tornado-no-spill/8Routers.madl

# 仅有活锁的 2×2 网格
stack exec -- dlockdetect -f examples/MaDL/complex_systems_examples/network_2x2.madl