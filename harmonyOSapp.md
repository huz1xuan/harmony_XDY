harmony分为har和app两种安装包，hap为调试包，app为上架包

首先下载deveco studio或者单独下载hdc工具并将添加hdc到系统环境变量

Windows环境变量设置方法：

按下Windows键，搜索栏输入“设置”，点击进入设置窗口；

在搜索栏中搜索“查看高级系统设置”。在环境变量>系统变量>Path>编辑中，将hdc.exe所在目录添加到Path。环境变量配置完成后，请重启电脑，即可在命令行窗口执行hdc命令。

Linux/MacOS系统：

打开终端工具，执行以下命令，根据输出结果分别执行不同的命令。

echo $SHELL
如果输出结果为bin/bash，执行以下命令打开.bashrc文件。

vi ~/.bashrc
如果输出结果为/bin/zsh，执行以下命令打开.zshrc文件。

vi ~/.zshrc
切换至英文输入法，按下键盘字母“i”，进入Insert模式。

在文件末尾添加PATH信息。

export PATH={DevEco Studio}/sdk/default/openharmony/toolchains:$PATH
其中{DevEco Studio}需替换为DevEco Studio实际安装目录的绝对路径，例如/home/DevEco-Studio。

编辑完成后，单击Esc键退出编辑模式，输入“:wq”并且单击Enter键保存。

请执行以下命令，使配置的环境变量生效。

如果步骤1打开的是.bashrc文件，请执行如下命令：

source ~/.bashrc
如果步骤1打开的是.zshrc文件，请执行如下命令：

source ~/.zshrc
环境变量配置完成后，重启系统。（这一步可以让AI帮忙配置）

配置完成后运行hdc install 文件目录即可安装成功