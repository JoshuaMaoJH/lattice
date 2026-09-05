# ADR-005 画布坐标与语义模型分离存储

## 背景

节点图既有语义（哪个节点连哪个引脚）又有呈现（节点在画布上的位置）。如果混在一起存，挪动一个节点就会让 `git diff` 出现变化，掩盖真正的逻辑改动。

## 决策

页面 JSON 中，语义在 `hierarchy` / `graph`，坐标单独放在 `layout` 字段，键为节点 ID。

```json
{
  "graph": { "nodes": [...], "edges": [...] },
  "layout": { "n_count": [120, 80], "n_fmt": [340, 80] }
}
```

## 后果

**好的**：整理画布不产生语义 diff；review 时可以只看 `graph`；未来做图 ↔ 文本 DSL 双向同步（R18）时，`graph` 已经是规范化的语义模型，不必先剥离呈现信息。

**代价**：两处都要维护节点 ID 的一致性；删除节点要记得清理 `layout`（陈旧的 `layout` 条目无害，只是冗余）。

## 实现

- `packages/lattice_core/lib/src/model/page.dart`（`CanvasPos`）
- 测试：`serialization_test.dart` 中 "canvas positions live outside the semantic model"
