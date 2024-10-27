![Recording](vhs/vhs.gif)

`nvim-rimecmd`是通过[rimecmd](https://github.com/suguruwataru/rimecmd)来在[Neovim](https://neovim.io/)中使用[librime](https://github.com/rime/librime)的Neovim插件。

nvim-rimecmd要在能运行以下命令的环境中才能使用：

- [rimecmd](https://github.com/suguruwataru/rimecmd)
- cat
- sh
- mkfifo

如果缺少了其中哪个的话，我也不知道会发生什么。

## 安装

这个代码仓库的目录结构就是标准的Vimscript插件的目录结构。所以，如果你没有其它插件的话，可以直接把这个这个仓库克隆下来然后移动成为你的Neovim配置目录。

当然了，现在人不太会这么安装插件了。你可以用，比方说[vim-plug](https://github.com/junegunn/vim-plug)，来安装这个插件。

```
Plug 'suguruwataru/nvim-rimecmd'
```

用别的插件管理插件应当也没问题，不过我没试过。

## 使用

这个插件提供了一个命令：`Rimecmd`。

使用这个命令可以进入一个“Rimecmd状态”。在这个状态下进入插入模式，这个插件就会通过一个窗口来让用户使用输入法。

在这个状态下再度使用`Rimecmd`就能解除这个状态。

在Neovim中使用`:h nvim-rimecmd`可以看到更多。

这个插件提供了中文文档。可以在`set helplang=zh`之后`:h nvim-rimecmd`查看。
