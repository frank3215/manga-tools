# patches

针对上游 [zyddnys/manga-image-translator](https://github.com/zyddnys/manga-image-translator)
的本地补丁。基线 commit：`95227a2`。

## manga-image-translator-sakura-fix.patch

修改 `manga_translator/translators/sakura.py`：

1. **返回值兜底**：`_handle_translation_request` 的结果先 `str()` 再参与字符串拼接，
   避免返回 `list` 时抛 `TypeError`。
2. **失败即抛错**：重试耗尽后由 `return prompt` 改为抛 `RuntimeError`。
   原实现会静默返回未翻译原文，产出「成功但没翻译」的图片，让批量脚本误判为 OK；
   改抛异常后该图片明确失败，由 `translate-all.sh` 计入 FAIL 并在下一轮重试。

应用：

```bash
cd manga-image-translator
git apply ../patches/manga-image-translator-sakura-fix.patch
```

撤销：

```bash
git apply -R ../patches/manga-image-translator-sakura-fix.patch
```

上游版本变动后若补丁冲突，直接手改 `sakura.py` 里对应的两处即可，逻辑很短。
