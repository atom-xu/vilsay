# DashScope 接口隔离联调（curl）

在接入 Swift 前，用命令行确认 **Token** 与请求体正确；401/403 多为 Key 或 `Bearer` 格式问题。

## 环境

```bash
export DASHSCOPE_API_KEY='你的Key'   # 勿有多余空格/换行
```

## 模型列表（与 App 内「拉取模型列表」一致）

原生列表（JSON 为 `output.models[].model`，需分页时加 `page_size` / `page_no`）：

```bash
curl -sS 'https://dashscope.aliyuncs.com/api/v1/models?page_size=20&page_no=1' \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY"
```

OpenAI 兼容列表（`data[].id`）：

```bash
curl -sS 'https://dashscope.aliyuncs.com/compatible-mode/v1/models' \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY"
```

HTTP 200 且能解析出模型 ID 即通路正常；App 内润色默认走 **原生 text-generation**，带 `厂商/模型` 形态的 ID 会走 **compatible-mode chat/completions**（见 `AppConfig.polishUsesOpenAICompatChatCompletions`）。

## Qwen 文本生成（非流式，验证 Key）

```bash
curl -sS 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation' \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen-turbo","input":{"messages":[{"role":"user","content":"hi"}]},"parameters":{"result_format":"message"}}'
```

HTTP 200 且 JSON 含 `output.choices` 即鉴权与模型名正常。

## Qwen 流式（SSE）

```bash
curl -N -sS 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation' \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
  -H 'Content-Type: application/json' \
  -H 'X-DashScope-SSE: enable' \
  -d '{"model":"qwen-turbo","input":{"messages":[{"role":"user","content":"说两个字"}]},"parameters":{"result_format":"message","incremental_output":true}}'
```

应看到多行 `data:{...}`。

## Paraformer 异步（录音文件识别）

需公网 `file_urls`；与麦克风本地文件无关，仅用于验证异步任务链路。

```bash
curl -sS 'https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription' \
  -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
  -H 'Content-Type: application/json' \
  -H 'X-DashScope-Async: enable' \
  -d '{"model":"paraformer-v2","input":{"file_urls":["https://example.com/sample.wav"]},"parameters":{"channel_id":[0]}}'
```

以上通了再在 Xcode 里接 `DASHSCOPE_PARAFORMER_FILE_URL` 与 App 内逻辑。
