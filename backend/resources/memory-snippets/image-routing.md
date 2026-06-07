<!-- cc-mimo-rescue:start -->
When the user asks about images, screenshots, charts, PDFs containing images, or local image paths, do not use Read on binary files and do not send image/base64 content to the main MiMo Pro route.

Use a Claude/Haiku subagent first (`subagent_type: "claude"`, `model: "haiku"`). CC Switch should route that image helper to `mimo-v2.5`. The helper should convert the image into text using local tools, OCR, or image analysis, then return the text summary to the main conversation.
<!-- cc-mimo-rescue:end -->
