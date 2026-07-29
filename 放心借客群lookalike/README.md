# 放心借客群 lookalike

放心借客群 lookalike 建模项目资料库，包含客群表结构、特征变量说明及外部数据字典。

## 目录

| 文件 | 说明 |
| --- | --- |
| `客群及其他相关表.md` | 客群明细表、用户信息表、授信表等关联说明 |
| `放心借特征变量.md` | 放心借特征变量定义 |
| `朴道-外部字典.md` | 朴道外部数据字典 |
| `百行-外部字典.md` | 百行外部数据字典 |
| `腾讯-外部字典.md` | 腾讯外部数据字典 |

## 发布为独立仓库

本项目应作为独立 GitHub 仓库使用（类似 [hirag-prod](https://github.com/Stardust269/hirag-prod)），以便在 Cursor 网页端直接选中该仓库。

在 GitHub 上创建空仓库 `放心借客群lookalike` 后，在本地执行：

```bash
git clone https://github.com/Stardust269/Stardust269.git
cd Stardust269
git fetch origin fxj-lookalike-standalone
git checkout fxj-lookalike-standalone
git remote add lookalike https://github.com/Stardust269/放心借客群lookalike.git
git push -u lookalike fxj-lookalike-standalone:main
```

也可直接运行仓库内的 `publish-as-standalone-repo.sh` 脚本。
