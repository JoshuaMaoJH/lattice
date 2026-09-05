# 项目页

`index.html` 是 Lattice 的项目页，自包含：没有外部脚本、字体或图片，
拷到任何静态托管上就能用。

它的签名特性是那块「图 ↔ 代码」对照面板：把鼠标放到一个节点上，它变成的那几行
Dart 会亮起来。这条对应关系不是演出来的——节点 ID 真的以注释的形式留在生成的
代码里（§8），面板只是把这件事显示出来。

代码块逐字节取自 `packages/lattice_codegen/test/goldens/counter_home_page.dart.txt`。
**改了生成器就要同步这里**，否则页面会开始撒谎。

也发布了一份可直接分享的版本：
<https://claude.ai/code/artifact/6f1bb838-5ad3-402d-9f11-2425c5c6c442>
