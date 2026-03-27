将 Whisper CoreML 模型嵌入 App（离线、免 Hugging Face 下载）
============================================================

1. 在本机用 WhisperKit 成功下载过一次后，模型通常在：
   ~/Library/Containers/<你的BundleId>/Data/Library/Application Support/huggingface/
   或 Hub 缓存中的 argmaxinc/whisperkit-coreml 下对应 openai_whisper-base 目录。

2. 复制整个「openai_whisper-base」文件夹（内含 MelSpectrogram / AudioEncoder / TextDecoder 等 .mlmodelc）。

3. 在 Xcode 中：把该文件夹放到本目录旁，保持名称为 openai_whisper-base；
   选中文件夹 → Target → Build Phases → Copy Bundle Resources → 添加。

4. 运行 App 后，WhisperASRFallback 会优先使用包内路径，download=false，不访问网络。

（体积约百 MB，Git 可用 Git LFS 或勿提交，仅本地/CI 打包。）
